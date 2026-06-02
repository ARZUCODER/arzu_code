import 'dart:async';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/tool_call.dart';
import 'permissions_service.dart';
import 'process_manager.dart';
import 'rag_service.dart';
import 'tool_executor.dart';

const _maxOutput = 12000; // LIMIT KAMAYTIRILDI (Tokenlarni tejash uchun)

ToolExecutor makeExecutor(PermissionsService perms, RagService ragService) => IoToolExecutor(perms, ragService);

class IoToolExecutor implements ToolExecutor {
  final PermissionsService perms;
  final RagService ragService;

  IoToolExecutor(this.perms, this.ragService);

  @override
  bool get supportsLocalTools => true;

  @override
  Future<ToolResult> invoke(
      String name,
      Map<String, Object?> args, {
        bool Function()? isCancelled,
      }) async {
    try {
      switch (name) {
        case 'semantic_search':
          return await _semanticSearch(args);
        case 'list_dir':
          return await _listDir(args);
        case 'read_file':
          return await _readFile(args);
        case 'write_file':
          return await _writeFile(args);
        case 'edit_file':
          return await _editFile(args);
        case 'make_dir':
          return await _makeDir(args);
        case 'path_exists':
          return await _pathExists(args);
        case 'search_text':
          return await _searchText(args, isCancelled);
        case 'run_command':
          return await _runCommand(args, isCancelled);
        case 'create_project':
          return await _createProject(args);
        case 'file_tree':
          return await _fileTree(args);
        case 'download_asset':
          return await _downloadAsset(args);
        case 'generate_image':
          return await _generateImage(args);
        case 'start_background_process':
          return await _startBackgroundProcess(args);
        case 'read_process_output':
          return await _readProcessOutput(args);
        case 'list_processes':
          return await _listProcesses(args);
        case 'stop_process':
          return await _stopProcess(args);
        default:
          return ToolResult(ok: false, error: 'Unknown tool: $name');
      }
    } catch (e) {
      return ToolResult(ok: false, error: e.toString());
    }
  }

  String _expandHome(String path) {
    final home = Platform.environment['HOME'] ?? '';
    if (path == '~') return home;
    if (path.startsWith('~/')) return p.join(home, path.substring(2));
    return path;
  }

  String _resolve(String path) => p.normalize(p.absolute(_expandHome(path)));

  String _clip(String s) {
    if (s.length <= _maxOutput) return s;
    return '${s.substring(0, _maxOutput)}\n\n[TRUNCATED: remaining ${s.length - _maxOutput} chars hidden to save tokens]';
  }

  ToolResult? _checkPath(String target) {
    final reason = perms.pathDenialReason(target);
    if (reason != null) return ToolResult(ok: false, error: reason);
    return null;
  }

  Future<ToolResult> _semanticSearch(Map<String, Object?> a) async {
    final cwdArg = a['cwd'] as String?;
    final cwd = cwdArg != null && cwdArg.isNotEmpty
        ? _resolve(cwdArg)
        : (perms.config.allowedFolders.isNotEmpty
        ? perms.config.allowedFolders.first
        : null);

    if (cwd == null) return const ToolResult(ok: false, error: 'No working directory set.');
    final denied = _checkPath(cwd);
    if (denied != null) return denied;

    final query = a['query'] as String? ?? '';
    if (query.isEmpty) return const ToolResult(ok: false, error: 'Query cannot be empty');

    final results = await ragService.semanticSearch(cwd, query, config: perms.config);
    return ToolResult(ok: true, output: results.join('\n\n'));
  }

  Future<ToolResult> _listDir(Map<String, Object?> a) async {
    final target = _resolve(a['path'] as String);
    final denied = _checkPath(target);
    if (denied != null) return denied;
    final dir = Directory(target);
    if (!dir.existsSync()) return ToolResult(ok: false, error: 'No such directory: $target');

    final entries = dir.listSync();
    final lines = entries.map((e) {
      final base = p.basename(e.path);
      return e is Directory ? '$base/' : base;
    }).toList()..sort();

    return ToolResult(ok: true, output: _clip(lines.join('\n')).trim().isEmpty ? '(empty directory)' : _clip(lines.join('\n')));
  }

  Future<ToolResult> _readFile(Map<String, Object?> a) async {
    final target = _resolve(a['path'] as String);
    final denied = _checkPath(target);
    if (denied != null) return denied;
    final file = File(target);
    if (!file.existsSync()) return ToolResult(ok: false, error: 'No such file: $target');

    final content = await file.readAsString();
    final lines = content.split('\n');
    final numbered = <String>[];
    for (var i = 0; i < lines.length; i++) {
      numbered.add('${(i + 1).toString().padLeft(4)} | ${lines[i]}');
    }
    return ToolResult(ok: true, output: _clip(numbered.join('\n')));
  }

  Future<ToolResult> _writeFile(Map<String, Object?> a) async {
    final target = _resolve(a['path'] as String);
    final denied = _checkPath(target);
    if (denied != null) return denied;
    final content = a['content'] as String? ?? '';
    final file = File(target);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return ToolResult(ok: true, output: 'Wrote ${content.length} bytes to $target');
  }

  Future<ToolResult> _editFile(Map<String, Object?> a) async {
    final target = _resolve(a['path'] as String);
    final denied = _checkPath(target);
    if (denied != null) return denied;

    final file = File(target);
    if (!file.existsSync()) return ToolResult(ok: false, error: 'No such file: $target');

    final startLine = (a['start_line'] as num?)?.toInt();
    final endLine = (a['end_line'] as num?)?.toInt();
    final replacement = a['replacement_text'] as String? ?? '';

    if (startLine == null || endLine == null) return const ToolResult(ok: false, error: 'start_line and end_line are required');

    final lines = (await file.readAsString()).split('\n');
    if (startLine < 1 || startLine > lines.length || endLine < startLine || endLine > lines.length) {
      return ToolResult(ok: false, error: 'Invalid line range. File has ${lines.length} lines.');
    }

    final replacementLines = replacement.isEmpty ? <String>[] : replacement.split('\n');
    lines.replaceRange(startLine - 1, endLine, replacementLines);

    await file.writeAsString(lines.join('\n'));
    return ToolResult(ok: true, output: 'Successfully replaced lines $startLine to $endLine.');
  }

  Future<ToolResult> _makeDir(Map<String, Object?> a) async {
    final target = _resolve(a['path'] as String);
    final denied = _checkPath(target);
    if (denied != null) return denied;
    await Directory(target).create(recursive: true);
    return ToolResult(ok: true, output: 'Created directory $target');
  }

  Future<ToolResult> _pathExists(Map<String, Object?> a) async {
    final target = _resolve(a['path'] as String);
    final denied = _checkPath(target);
    if (denied != null) return denied;
    if (Directory(target).existsSync()) return const ToolResult(ok: true, output: 'directory');
    if (File(target).existsSync()) return const ToolResult(ok: true, output: 'file');
    return const ToolResult(ok: true, output: 'does not exist');
  }

  Future<ToolResult> _searchText(Map<String, Object?> a, bool Function()? isCancelled) async {
    final target = _resolve(a['path'] as String);
    final denied = _checkPath(target);
    if (denied != null) return denied;
    final query = a['query'] as String? ?? '';
    final useRg = await _commandExists('rg');
    final cmd = useRg ? 'rg' : 'grep';
    final cmdArgs = useRg ? ['-n', '--no-heading', '-S', query, target] : ['-rn', query, target];
    return _runRaw(cmd, cmdArgs, target, isCancelled);
  }

  Future<ToolResult> _runCommand(Map<String, Object?> a, bool Function()? isCancelled) async {
    final command = a['command'] as String? ?? '';
    final blocked = perms.blockedCommandPattern(command);
    if (blocked != null) return ToolResult(ok: false, error: 'Command blocked by safety filter (matched "$blocked")');
    final cwdArg = a['cwd'] as String?;
    final cwd = cwdArg != null && cwdArg.isNotEmpty ? _resolve(cwdArg) : (perms.config.allowedFolders.isNotEmpty ? perms.config.allowedFolders.first : null);
    if (cwd == null) return const ToolResult(ok: false, error: 'No working directory set.');
    final denied = _checkPath(cwd);
    if (denied != null) return denied;
    return _runRaw('/bin/zsh', ['-lc', command], cwd, isCancelled);
  }

  Future<ToolResult> _createProject(Map<String, Object?> a) async {
    final parent = _resolve(a['parent_dir'] as String);
    final denied = _checkPath(parent);
    if (denied != null) return denied;
    final name = a['name'] as String;
    final kind = a['kind'] as String? ?? 'generic';
    final dir = p.join(parent, name);
    await Directory(dir).create(recursive: true);
    await File(p.join(dir, 'README.md')).writeAsString('# $name\n\nCreated by Arzu Code ($kind).\n');
    if (kind == 'node' || kind == 'web') {
      await File(p.join(dir, 'package.json')).writeAsString('{\n  "name": "$name",\n  "version": "0.1.0",\n  "type": "module"\n}\n');
    }
    return ToolResult(ok: true, output: 'Created project "$name" at $dir');
  }

  static const _treeIgnored = {
    '.git', 'node_modules', 'build', 'dist', '.dart_tool', '.pub-cache',
    '.idea', '.gradle', 'Pods', '.next', '.venv', '__pycache__',
  };

  Future<ToolResult> _fileTree(Map<String, Object?> a) async {
    final pathArg = a['path'] as String?;
    final target = (pathArg != null && pathArg.isNotEmpty) ? _resolve(pathArg) : (perms.config.allowedFolders.isNotEmpty ? perms.config.allowedFolders.first : null);
    if (target == null) return const ToolResult(ok: false, error: 'No working directory set.');
    final denied = _checkPath(target);
    if (denied != null) return denied;
    final dir = Directory(target);
    if (!dir.existsSync()) return ToolResult(ok: false, error: 'No such directory: $target');
    final maxDepth = (a['max_depth'] as num?)?.toInt() ?? 4;
    final buffer = StringBuffer('${p.basename(target)}/\n');
    _treeInto(dir, '', 0, maxDepth, buffer);
    return ToolResult(ok: true, output: _clip(buffer.toString()));
  }

  void _treeInto(Directory dir, String prefix, int depth, int maxDepth, StringBuffer out) {
    if (depth >= maxDepth) return;
    List<FileSystemEntity> entries;
    try { entries = dir.listSync(); } catch (_) { return; }
    entries.sort((x, y) {
      final xd = x is Directory ? 0 : 1;
      final yd = y is Directory ? 0 : 1;
      if (xd != yd) return xd - yd;
      return p.basename(x.path).toLowerCase().compareTo(p.basename(y.path).toLowerCase());
    });
    entries = entries.where((e) => !_treeIgnored.contains(p.basename(e.path))).toList();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final last = i == entries.length - 1;
      final branch = last ? '└── ' : '├── ';
      final name = p.basename(e.path);
      if (e is Directory) {
        out.writeln('$prefix$branch$name/');
        _treeInto(e, '$prefix${last ? '    ' : '│   '}', depth + 1, maxDepth, out);
      } else {
        out.writeln('$prefix$branch$name');
      }
    }
  }

  Future<ToolResult> _downloadAsset(Map<String, Object?> a) async {
    final url = a['url'] as String? ?? '';
    final savePath = a['save_path'] as String? ?? '';
    if (url.isEmpty || savePath.isEmpty) return const ToolResult(ok: false, error: 'url and save_path are required.');
    final target = _resolve(savePath);
    final denied = _checkPath(target);
    if (denied != null) return denied;
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return ToolResult(ok: false, error: 'Download failed: HTTP ${res.statusCode}');
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(res.bodyBytes);
      return ToolResult(ok: true, output: 'Downloaded ${res.bodyBytes.length} bytes to $target');
    } catch (e) {
      return ToolResult(ok: false, error: 'Download error: $e');
    }
  }

  Future<ToolResult> _generateImage(Map<String, Object?> a) async {
    final prompt = a['prompt'] as String? ?? '';
    final savePath = a['save_path'] as String? ?? '';
    if (prompt.isEmpty || savePath.isEmpty) return const ToolResult(ok: false, error: 'prompt and save_path required.');
    final target = _resolve(savePath);
    final denied = _checkPath(target);
    if (denied != null) return denied;
    try {
      final model = FirebaseAI.vertexAI().generativeModel(
        model: perms.config.imageModel,
        generationConfig: GenerationConfig(responseModalities: [ResponseModalities.text, ResponseModalities.image]),
      );
      final response = await model.generateContent([Content.text(prompt)]);
      final images = response.inlineDataParts.toList();
      if (images.isEmpty) return ToolResult(ok: false, error: 'Model returned no image.');
      final part = images.first;
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(part.bytes);
      return ToolResult(ok: true, output: 'Generated image and saved to $target');
    } catch (e) {
      return ToolResult(ok: false, error: 'Image generation failed: $e');
    }
  }

  Future<ToolResult> _startBackgroundProcess(Map<String, Object?> a) async {
    final command = a['command'] as String? ?? '';
    if (command.isEmpty) return const ToolResult(ok: false, error: 'command required.');
    final blocked = perms.blockedCommandPattern(command);
    if (blocked != null) return ToolResult(ok: false, error: 'Blocked by safety filter.');
    final cwdArg = a['cwd'] as String?;
    final cwd = cwdArg != null && cwdArg.isNotEmpty ? _resolve(cwdArg) : (perms.config.allowedFolders.isNotEmpty ? perms.config.allowedFolders.first : null);
    if (cwd == null) return const ToolResult(ok: false, error: 'No working directory set.');
    final denied = _checkPath(cwd);
    if (denied != null) return denied;

    final mp = await ProcessManager.instance.start(command: command, cwd: cwd, label: a['name'] as String?);
    await Future.delayed(const Duration(milliseconds: 1200));
    final early = mp.tail(maxChars: 1500);
    return ToolResult(ok: true, output: 'Started bg process "${mp.id}". Output so far:\n$early');
  }

  Future<ToolResult> _readProcessOutput(Map<String, Object?> a) async {
    final id = a['id'] as String? ?? '';
    final mp = ProcessManager.instance.byId(id);
    if (mp == null) return ToolResult(ok: false, error: 'No bg process with id "$id".');
    final status = mp.running ? 'RUNNING' : 'EXITED (code ${mp.exitCode})';
    return ToolResult(ok: true, output: '[$id · $status]\n${mp.tail(maxChars: 8000)}');
  }

  Future<ToolResult> _listProcesses(Map<String, Object?> a) async {
    final procs = ProcessManager.instance.processes;
    if (procs.isEmpty) return const ToolResult(ok: true, output: 'No background processes.');
    final lines = procs.map((mp) => '${mp.id}  [${mp.running ? 'running' : 'exited'}]  ${mp.command}').join('\n');
    return ToolResult(ok: true, output: lines);
  }

  Future<ToolResult> _stopProcess(Map<String, Object?> a) async {
    final id = a['id'] as String? ?? '';
    final ok = ProcessManager.instance.stop(id);
    return ok ? ToolResult(ok: true, output: 'Stopped "$id".') : ToolResult(ok: false, error: 'Not found.');
  }

  Future<bool> _commandExists(String cmd) async {
    try {
      final res = await Process.run('which', [cmd]);
      return res.exitCode == 0;
    } catch (_) { return false; }
  }

  Future<ToolResult> _runRaw(String cmd, List<String> args, String cwd, bool Function()? isCancelled) async {
    final process = await Process.start(cmd, args, workingDirectory: cwd);
    final out = StringBuffer();
    final err = StringBuffer();

    process.stdout.listen((d) => out.write(String.fromCharCodes(d)));
    process.stderr.listen((d) => err.write(String.fromCharCodes(d)));

    var timedOut = false;
    var userAborted = false;

    Timer? cancelTimer;
    if (isCancelled != null) {
      cancelTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (isCancelled()) {
          userAborted = true;
          try { process.kill(ProcessSignal.sigkill); } catch (_) {}
          timer.cancel();
        }
      });
    }

    final exitCode = await process.exitCode.timeout(const Duration(seconds: 300), onTimeout: () {
      timedOut = true;
      try { process.kill(ProcessSignal.sigkill); } catch (_) {}
      return -1;
    });

    cancelTimer?.cancel();

    var combined = [out.toString(), err.toString()].where((s) => s.isNotEmpty).join('\n');
    if (userAborted) combined += '\n\n[ABORTED BY USER]';
    else if (timedOut) combined += '\n\n[KILLED: Timeout]';

    combined = _clip(combined);

    return ToolResult(
      ok: exitCode == 0 && !timedOut && !userAborted,
      output: combined.isEmpty ? '(exit $exitCode)' : combined,
      error: (exitCode == 0 && !timedOut && !userAborted) ? null : 'exit code $exitCode',
    );
  }
}