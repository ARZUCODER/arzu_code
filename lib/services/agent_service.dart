import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart' as fbai;
import 'package:google_generative_ai/google_generative_ai.dart' as gai;
import 'package:path/path.dart' as p;

import '../models/app_config.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import 'arzu_cloud_service.dart';
import 'environment_service.dart';
import 'permissions_service.dart';
import 'tool_executor.dart';
import 'tool_registry.dart';

class AgentService {
  final ToolExecutor executor;
  final PermissionsService perms;

  // Big multi-stage tasks need many tool rounds; 15 was cutting them off mid-task.
  // The failure guard + history compaction keep this safe from runaway cost.
  static const int maxIterations = 40;

  // Token discipline: keep full output only for the last N tool rounds within a
  // turn; older big outputs get stubbed so they stop re-inflating every request.
  static const int _keepFullToolRounds = 2;
  static const int _toolStubThreshold = 350; // chars; only stub outputs bigger than this
  // Stop runaway "try-fail-retry" loops: bail after this many failing rounds in a row.
  static const int _maxConsecutiveFailures = 3;
  // Some cloud models (qwen/gemma via Ollama) describe a plan but forget to call the
  // tool, ending the turn early. Nudge them to actually act, up to this many times.
  static const int _maxNudges = 3;
  // Stop if the EXACT same tool error repeats this many times in a turn — catches
  // the "model keeps reintroducing the same bug" loop (e.g. qwen's argParser).
  static const int _maxSameError = 3;

  AgentService({required this.executor, required this.perms});

  int _counter = 0;
  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// One cheap call to name a session: returns a short (<=4 words) title in the
  /// user's language using the active engine. Best-effort — returns null on failure.
  Future<String?> quickTitle(AppConfig config, String firstUserMsg) async {
    final msg = firstUserMsg.length > 400 ? firstUserMsg.substring(0, 400) : firstUserMsg;
    final prompt = 'Quyidagi so‘rov uchun juda qisqa sarlavha yoz (eng ko‘pi 4 so‘z, tirnoqsiz, '
        'foydalanuvchi tilida, nuqtasiz). Faqat sarlavhani qaytar:\n"$msg"';
    try {
      if (config.useLocalModel) {
        final cloud = ArzuCloudService(baseUrl: config.arzuCloudUrl, apiKey: config.arzuCloudKey);
        final buf = StringBuffer();
        await for (final c in cloud.streamChat(model: config.localModel, messages: [{'role': 'user', 'content': prompt}], temperature: 0.2)) {
          if (c.text != null) buf.write(c.text);
        }
        return _cleanTitle(buf.toString());
      }
      final engine = config.customModelEngines[config.activeModel] ?? (kGoogleAiModels.contains(config.activeModel) ? 'google' : 'vertex');
      if (engine == 'google') {
        if (config.googleApiKey.trim().isEmpty) return null;
        final model = gai.GenerativeModel(model: 'gemini-3.1-flash-lite', apiKey: config.googleApiKey);
        final r = await model.generateContent([gai.Content.text(prompt)]);
        return _cleanTitle(r.text ?? '');
      }
      final model = fbai.FirebaseAI.vertexAI().generativeModel(model: 'gemini-2.5-flash');
      final r = await model.generateContent([fbai.Content.text(prompt)]);
      return _cleanTitle(r.text ?? '');
    } catch (_) {
      return null;
    }
  }

  String _cleanTitle(String s) {
    var t = s.trim().replaceAll('\n', ' ').replaceAll('"', '').replaceAll('`', '').replaceAll('*', '').trim();
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    if (t.length > 42) t = '${t.substring(0, 42)}…';
    return t;
  }

  String _getSystemPrompt(AppConfig config, {bool withToolProtocol = false}) {
    // STATIC parts first (identical every request) so Vertex/Gemini implicit
    // caching can reuse the long prefix cheaply; DYNAMIC bits (date, folders) last.
    String prompt = kSystemPrompt;
    if (EnvironmentService.promptBlock != null) prompt += EnvironmentService.promptBlock!;
    if (withToolProtocol) prompt += buildToolProtocolText();

    // --- dynamic tail (changes between requests; kept at the very end) ---
    final now = DateTime.now();
    const days = ['', 'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'];
    const months = ['', 'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentyabr', 'oktyabr', 'noyabr', 'dekabr'];
    String two(int n) => n.toString().padLeft(2, '0');
    String full(DateTime d) => '${d.year}-yil ${d.day}-${months[d.month]} (${days[d.weekday]})';
    final y = now.subtract(const Duration(days: 1));
    final t = now.add(const Duration(days: 1));
    if (config.allowedFolders.isNotEmpty) {
      prompt += '\n\n# ALLOWED WORKSPACE PATHS\n';
      for (final f in config.allowedFolders) {
        prompt += '- $f\n';
      }
    }
    prompt += '\n# DATE/TIME (host clock — facts, never recompute): Bugun ${full(now)} ${two(now.hour)}:${two(now.minute)} · Kecha ${full(y)} · Ertaga ${full(t)}';
    return prompt;
  }

  Future<void> runTurn({
    required AppConfig config,
    required String userText,
    required List<ChatMessage> priorMessages,
    required ChatMessage assistant,
    required void Function() onUpdate,
    required Future<bool> Function(ToolCall) requestApproval,
    bool Function()? isCancelled,
    List<String> attachments = const [],
  }) async {
    if (config.useLocalModel) {
      await _runCloudTurn(config, userText, priorMessages, assistant, onUpdate, requestApproval, isCancelled);
      return;
    }

    if (isClaudeCliModel(config.activeModel)) {
      await _runClaudeCliTurn(config, userText, priorMessages, assistant, onUpdate, isCancelled);
      return;
    }

    String engine = config.customModelEngines[config.activeModel] ?? (kGoogleAiModels.contains(config.activeModel) ? 'google' : 'vertex');

    if (engine == 'google') {
      if (config.googleApiKey.trim().isEmpty) {
        assistant.error = 'Google Generative AI requires an API Key. Please add it in Settings.';
        onUpdate();
        return;
      }
      await _runGoogleAiTurn(config, userText, priorMessages, assistant, onUpdate, requestApproval, isCancelled, attachments);
    } else {
      await _runVertexTurn(config, userText, priorMessages, assistant, onUpdate, requestApproval, isCancelled, attachments);
    }
  }

  String _mimeForImage(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png': return 'image/png';
      case '.jpg': case '.jpeg': return 'image/jpeg';
      case '.gif': return 'image/gif';
      case '.webp': return 'image/webp';
      default: return 'image/png';
    }
  }

  void _extractToolCallFromJson(ChatMessage assistant, List<dynamic> currentToolCalls) {
    if (currentToolCalls.isNotEmpty) return;
    String text = assistant.text.trim();
    if (text.isEmpty) return;
    if (text.contains('```json')) text = text.split('```json').last.split('```').first.trim();
    else if (text.contains('```')) text = text.split('```').last.split('```').first.trim();
    if (text.contains('"name"') && (text.contains('"arguments"') || text.contains('"args"'))) {
      String arrayText = text.replaceAll(RegExp(r'\}\s*\{'), '},{');
      if (!arrayText.startsWith('[')) arrayText = '[$arrayText]';
      if (!arrayText.endsWith(']')) arrayText = '$arrayText]';
      try {
        final parsedList = jsonDecode(arrayText);
        if (parsedList is List) {
          bool found = false;
          for (final item in parsedList) {
            if (item is Map && item.containsKey('name')) {
              currentToolCalls.add({'function': {'name': item['name'], 'arguments': item['arguments'] ?? item['args'] ?? {}}});
              found = true;
            }
          }
          if (found) assistant.text = '';
        }
      } catch (_) {}
    }
  }

  String _errorSig(String? err) {
    if (err == null || err.isEmpty) return 'err';
    final firstLine = err.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => err).trim();
    return firstLine.length > 80 ? firstLine.substring(0, 80) : firstLine;
  }

  // Tallies failing tool results by (tool + error) signature; returns the signature
  // that has now repeated _maxSameError times, or '' if none is stuck yet.
  String _trackStuck(Map<String, int> counts, Iterable<ToolCall> executed) {
    for (final tc in executed) {
      final r = tc.result;
      if (r != null && !r.ok) {
        final sig = '${tc.name}:${_errorSig(r.error)}';
        counts[sig] = (counts[sig] ?? 0) + 1;
        if (counts[sig]! >= _maxSameError) return sig;
      }
    }
    return '';
  }

  // Returns a copy of args with big string values (e.g. a whole written file)
  // replaced by a short stub, or null if nothing was large enough to stub.
  Map<String, Object?>? _stubArgs(Map<String, Object?> args) {
    Map<String, Object?>? out;
    for (final e in args.entries) {
      final v = e.value;
      if (v is String && v.length > _toolStubThreshold) {
        out ??= Map<String, Object?>.from(args);
        out[e.key] = '[${v.length} chars omitted to save tokens]';
      }
    }
    return out;
  }

  // Compact a maps-based chat history (Arzu Cloud path): stub the body of older
  // 'tool' results AND the args of older tool CALLS (write_file content etc.) so
  // big payloads stop re-billing on every request.
  void _compactCloudHistory(List<Map<String, dynamic>> history) {
    final toolIdx = <int>[];
    for (var i = 0; i < history.length; i++) {
      if (history[i]['role'] == 'tool') toolIdx.add(i);
    }
    if (toolIdx.length <= _keepFullToolRounds) return;
    final keepFrom = toolIdx[toolIdx.length - _keepFullToolRounds];
    for (var i = 0; i < keepFrom; i++) {
      final m = history[i];
      if (m['role'] == 'tool') {
        final content = m['content'];
        if (content is String && content.length > _toolStubThreshold) {
          m['content'] = '[earlier result of ${m['name'] ?? 'tool'} omitted (${content.length} chars) to save tokens]';
        }
      } else if (m['role'] == 'assistant' && m['tool_calls'] is List) {
        for (final tc in (m['tool_calls'] as List)) {
          final fn = tc is Map ? tc['function'] : null;
          if (fn is Map && fn['arguments'] is Map) {
            final stubbed = _stubArgs(Map<String, Object?>.from(fn['arguments'] as Map));
            if (stubbed != null) fn['arguments'] = stubbed;
          }
        }
      }
    }
  }

  String _shArg(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// Runs the real `claude` (Claude Code) binary headlessly via `ollama launch`,
  /// driven by an Ollama model, and streams its output into the chat bubble.
  /// Claude Code does its own file edits/commands inside the working folder.
  Future<void> _runClaudeCliTurn(AppConfig config, String userText, List<ChatMessage> prior, ChatMessage assistant, void Function() onUpdate, bool Function()? isCancelled) async {
    final ollamaModel = claudeCliOllamaModel(config.activeModel);
    final home = Platform.environment['HOME'] ?? '';

    // Pick a working dir that ACTUALLY exists (a stale/deleted allowed folder
    // would make Process.start throw "No such file or directory").
    String cwd = '';
    for (final f in config.allowedFolders) {
      if (f.isNotEmpty && Directory(f).existsSync()) { cwd = f; break; }
    }
    if (cwd.isEmpty) cwd = (home.isNotEmpty && Directory(home).existsSync()) ? home : Directory.current.path;

    // GUI-launched macOS apps inherit a minimal PATH; build a solid one so
    // `ollama` (and the rest) resolve even when launched from /Applications.
    final env = Map<String, String>.from(Platform.environment);
    final paths = <String>{
      '/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin', '/usr/sbin', '/sbin',
      if (home.isNotEmpty) '$home/.local/bin',
      ...(env['PATH'] ?? '').split(':').where((p) => p.isNotEmpty),
    };
    env['PATH'] = paths.join(':');
    if (home.isNotEmpty) env['HOME'] = home;

    // Continue the most recent Claude session in this folder for multi-turn chat.
    // stream-json gives LIVE events (text + each tool use) instead of one final
    // dump after minutes of silence. --verbose is required with stream-json in -p.
    final cont = prior.isNotEmpty ? '--continue ' : '';
    final cmd = 'ollama launch claude --model ${_shArg(ollamaModel)} -y -- '
        '-p ${_shArg(userText)} $cont--permission-mode bypassPermissions '
        '--output-format stream-json --verbose';

    assistant.thinking = 'Claude CLI ishlamoqda ($ollamaModel)…';
    onUpdate();

    Process? proc;
    Timer? cancelTimer;
    try {
      // -ilc: interactive+login so ~/.zshrc (where users add tool paths) is sourced too.
      proc = await Process.start('/bin/zsh', ['-ilc', cmd], workingDirectory: cwd, environment: env);
      if (isCancelled != null) {
        cancelTimer = Timer.periodic(const Duration(milliseconds: 400), (t) {
          if (isCancelled()) {
            try { proc?.kill(ProcessSignal.sigkill); } catch (_) {}
            t.cancel();
          }
        });
      }
      final toolMap = <String, ToolCall>{};
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        final t = line.trim();
        if (t.isEmpty) return;
        try {
          _handleClaudeEvent(jsonDecode(t), assistant, onUpdate, toolMap);
        } catch (_) {
          // Not a JSON event (e.g. a stray log line) — show it as-is.
          assistant.text += (assistant.text.isEmpty ? '' : '\n') + t;
          onUpdate();
        }
      });
      final errBuf = StringBuffer();
      proc.stderr.transform(utf8.decoder).listen(errBuf.write);

      final code = await proc.exitCode;
      cancelTimer?.cancel();
      if (isCancelled?.call() ?? false) {
        if (assistant.text.trim().isEmpty) assistant.error = 'Stopped by user.';
      } else if (code != 0 && assistant.text.trim().isEmpty) {
        final err = errBuf.toString().trim();
        assistant.error = 'Claude CLI exited ($code).${err.isNotEmpty ? '\n$err' : ''}';
      }
    } catch (e) {
      cancelTimer?.cancel();
      assistant.error = 'Claude CLI ishga tushmadi: $e';
    } finally {
      assistant.thinking = null;
      onUpdate();
    }
  }

  // Renders Claude Code stream-json events live: text → bubble, each tool_use →
  // a real ToolCall so it shows in the same collapsed/expandable card as the
  // native engines (and the tool_result fills in its output).
  void _handleClaudeEvent(dynamic ev, ChatMessage assistant, void Function() onUpdate, Map<String, ToolCall> toolMap) {
    if (ev is! Map) return;
    final type = ev['type'];
    void add(String s) {
      if (s.trim().isEmpty) return;
      assistant.text += (assistant.text.isEmpty ? '' : '\n\n') + s.trim();
    }

    if (type == 'assistant') {
      final content = (ev['message'] is Map ? ev['message']['content'] : null) as List? ?? const [];
      for (final block in content) {
        if (block is! Map) continue;
        switch (block['type']) {
          case 'text':
            add((block['text'] ?? '').toString());
            break;
          case 'tool_use':
            final id = block['id']?.toString() ?? _id();
            final input = block['input'];
            final tc = ToolCall(
              id: id,
              name: block['name']?.toString() ?? 'tool',
              args: input is Map ? Map<String, Object?>.from(input) : <String, Object?>{},
              status: ToolStatus.running,
              textAnchor: assistant.text.length,
              startedAt: DateTime.now(),
            );
            assistant.toolCalls.add(tc);
            toolMap[id] = tc;
            assistant.thinking = tc.summary;
            break;
        }
      }
      onUpdate();
    } else if (type == 'user') {
      // Tool results come back as a user message with tool_result blocks.
      final content = (ev['message'] is Map ? ev['message']['content'] : null) as List? ?? const [];
      for (final block in content) {
        if (block is! Map || block['type'] != 'tool_result') continue;
        final tc = toolMap[block['tool_use_id']?.toString()];
        if (tc == null) continue;
        final out = _claudeResultText(block['content']);
        final isErr = block['is_error'] == true;
        tc.result = ToolResult(ok: !isErr, output: isErr ? null : out, error: isErr ? out : null);
        tc.status = isErr ? ToolStatus.error : ToolStatus.done;
        tc.completedAt = DateTime.now();
      }
      onUpdate();
    } else if (type == 'result') {
      final res = ev['result'];
      if (res is String && res.trim().isNotEmpty && !assistant.text.contains(res.trim())) {
        add(res);
      }
      // Claude CLI reports real token usage in the result event — surface it.
      final usage = ev['usage'];
      if (usage is Map) {
        assistant.inputTokens = (usage['input_tokens'] as num?)?.toInt() ?? assistant.inputTokens;
        assistant.outputTokens = (usage['output_tokens'] as num?)?.toInt() ?? assistant.outputTokens;
        assistant.totalTokens = assistant.inputTokens + assistant.outputTokens;
      }
      // Any tool still marked running (no explicit result) → mark done.
      for (final tc in assistant.toolCalls) {
        if (tc.status == ToolStatus.running) {
          tc.status = ToolStatus.done;
          tc.completedAt = DateTime.now();
        }
      }
      assistant.thinking = null;
      onUpdate();
    }
  }

  String _claudeResultText(dynamic content) {
    String s;
    if (content is String) {
      s = content;
    } else if (content is List) {
      s = content.map((b) => (b is Map && b['type'] == 'text') ? (b['text'] ?? '') : '').join('\n');
    } else {
      s = content?.toString() ?? '';
    }
    s = s.trim();
    return s.length > 4000 ? '${s.substring(0, 4000)}\n…(truncated)' : s;
  }

  Future<void> _runCloudTurn(AppConfig config, String userText, List<ChatMessage> priorMessages, ChatMessage assistant, void Function() onUpdate, Future<bool> Function(ToolCall) requestApproval, bool Function()? isCancelled) async {
    final cloud = ArzuCloudService(baseUrl: config.arzuCloudUrl, apiKey: config.arzuCloudKey);
    final nativeTools = cloudModelSupportsNativeTools(config.localModel);

    final history = <Map<String, dynamic>>[{'role': 'system', 'content': _getSystemPrompt(config, withToolProtocol: !nativeTools)}];
    for (final m in priorMessages) {
      if (m.text.trim().isNotEmpty) history.add({'role': m.role == MessageRole.user ? 'user' : 'assistant', 'content': m.text});
      if (m.toolCalls.isNotEmpty) {
        history.add({'role': 'assistant', 'content': '', 'tool_calls': m.toolCalls.map((tc) => {'type': 'function', 'function': {'name': tc.name, 'arguments': tc.args}}).toList()});
        for (final tc in m.toolCalls) {
          if (tc.result != null) history.add({'role': 'tool', 'name': tc.name, 'content': tc.result!.output ?? tc.result!.error ?? ''});
        }
      }
    }
    history.add({'role': 'user', 'content': userText});
    // gemma & friends have no tool API — they call tools via the text protocol.
    final tools = nativeTools ? buildOllamaTools() : <Map<String, dynamic>>[];

    assistant.thinking = 'Thinking (Arzu Cloud)...';
    onUpdate();
    var iterations = 0;
    var consecutiveFailures = 0;
    var nudges = 0;
    final errorCounts = <String, int>{};
    final editedFiles = <String>{};
    var autoVerified = false;
    while (iterations++ < maxIterations) {
      if (isCancelled?.call() ?? false) { assistant.error = 'Stopped by user.'; onUpdate(); return; }
      _compactCloudHistory(history);
      List<dynamic> currentToolCalls = [];
      final iterText = StringBuffer();
      var firstTextChunk = true;
      try {
        await for (final chunk in cloud.streamChat(model: config.localModel, messages: history, tools: tools, temperature: config.temperature, isCancelled: isCancelled)) {
          if (isCancelled?.call() ?? false) return;
          if (chunk.text != null && chunk.text!.isNotEmpty) {
            // Separate each round's narration so steps don't jam together.
            if (firstTextChunk && assistant.text.isNotEmpty && !assistant.text.endsWith('\n')) {
              assistant.text += '\n\n';
            }
            firstTextChunk = false;
            assistant.text += chunk.text!;
            iterText.write(chunk.text!);
            onUpdate();
          }
          if (chunk.toolCalls != null) currentToolCalls.addAll(chunk.toolCalls!);

          if (chunk.inputTokens != null) assistant.inputTokens += chunk.inputTokens!;
          if (chunk.outputTokens != null) {
            assistant.outputTokens += chunk.outputTokens!;
            assistant.totalTokens += (chunk.inputTokens ?? 0) + chunk.outputTokens!;
            onUpdate();
          }
        }
      } catch (e) {
        assistant.error = e.toString(); assistant.thinking = null; onUpdate(); return;
      }
      _extractToolCallFromJson(assistant, currentToolCalls);

      if (currentToolCalls.isEmpty) {
        final said = iterText.toString().trimRight();
        final isDone = said.toLowerCase().contains('bajarildi');
        // A question / empty reply is a genuine conversational stop (e.g. a greeting).
        // A statement of intent ("...ko'rib chiqaman.") with no tool call is the model
        // stalling — nudge it to actually execute instead of ending the turn.
        final looksConversational = said.isEmpty || said.endsWith('?');
        if (isDone || looksConversational || nudges >= _maxNudges) {
          // Before finishing, auto-verify any code edited this turn (once).
          if (!autoVerified && editedFiles.isNotEmpty && !(isCancelled?.call() ?? false)) {
            autoVerified = true;
            final errs = await _autoVerify(config, editedFiles, assistant, onUpdate, isCancelled);
            if (errs != null) {
              history.add({'role': 'user', 'content': errs});
              assistant.thinking = 'Xatolarni tuzatyapman…'; onUpdate();
              continue;
            }
          }
          break;
        }

        nudges++;
        // Keep the model's own preamble in the history so it sees what it promised.
        if (said.isNotEmpty) history.add({'role': 'assistant', 'content': said});
        history.add({
          'role': 'user',
          'content': 'Davom et. Faqat tasvirlab to‘xtama — aytgan ishingni HOZIR tegishli tool(lar)ni chaqirib bajar. '
              'Vazifa to‘liq tugaganda, va faqat o‘shanda, "Barcha vazifalar bajarildi!" deb yoz.'
        });
        assistant.thinking = 'Continuing…'; onUpdate();
        continue;
      }
      nudges = 0; // productive step — reset the stall budget

      history.add({'role': 'assistant', 'content': '', 'tool_calls': currentToolCalls});
      var roundHadFailure = false;
      final roundTools = <ToolCall>[];
      for (final call in currentToolCalls) {
        if (isCancelled?.call() ?? false) break;
        final func = call['function'];
        final tc = ToolCall(id: _id(), name: func['name'], args: Map<String, Object?>.from(func['arguments']), textAnchor: assistant.text.length, startedAt: DateTime.now());
        assistant.toolCalls.add(tc); roundTools.add(tc); assistant.thinking = tc.summary; onUpdate();

        if (!await _ensureAccess(tc, config, requestApproval)) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'Folder access denied.'); onUpdate();
          history.add({'role': 'tool', 'name': tc.name, 'content': 'User denied folder access.'});
          continue;
        }

        bool approved = !(executor.supportsLocalTools && tc.isMutating && perms.requiresApproval(tc.name, tc.ruleSignature)) || await (() { tc.status = ToolStatus.pending; onUpdate(); return requestApproval(tc); })();
        if (!approved) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'User denied.'); onUpdate();
          history.add({'role': 'tool', 'name': tc.name, 'content': 'User denied.'});
          continue;
        }
        tc.status = ToolStatus.running; onUpdate();
        final rawResult = await executor.invoke(tc.name, tc.args, isCancelled: isCancelled);
        tc.result = ToolResult(ok: rawResult.ok, error: rawResult.error, output: rawResult.output);
        tc.status = tc.result!.ok ? ToolStatus.done : ToolStatus.error; tc.completedAt = DateTime.now(); onUpdate();
        if (!tc.result!.ok) roundHadFailure = true;
        if (tc.result!.ok && _isFileEditTool(tc.name) && tc.args['path'] is String) {
          editedFiles.add(_resolvePath(tc.args['path'] as String, config));
          autoVerified = false; // new edits → allow another verify pass
        }
        history.add({'role': 'tool', 'name': tc.name, 'content': tc.result!.output ?? tc.result!.error ?? ''});
      }

      if (_trackStuck(errorCounts, roundTools).isNotEmpty) {
        assistant.text += '\n\n⚠️ Bir xil xato $_maxSameError marta takrorlandi — to‘xtatdim. Boshqacha yondashuv yoki qo‘shimcha ma‘lumot bering.';
        break;
      }
      if (_tripFailureGuard(roundHadFailure, () => ++consecutiveFailures, () => consecutiveFailures = 0, assistant)) break;
      assistant.thinking = 'Thinking (Arzu Cloud)...'; onUpdate();
    }
    assistant.thinking = null; onUpdate();
  }

  bool _isFileEditTool(String name) => name == 'write_file' || name == 'edit_file' || name == 'replace_in_file';

  // If a tool targets a path OUTSIDE the allowed folders, returns the folder we
  // should ask the user to grant access to (else null = already allowed / N/A).
  String? _accessFolderNeeded(ToolCall tc, AppConfig config) {
    String? raw;
    var isDir = false;
    switch (tc.name) {
      case 'create_project':
        raw = tc.args['parent_dir'] as String?; isDir = true; break;
      case 'run_command':
      case 'start_background_process':
      case 'semantic_search':
        raw = tc.args['cwd'] as String?; isDir = true; break;
      case 'make_dir':
      case 'list_dir':
      case 'file_tree':
      case 'path_exists':
        raw = tc.args['path'] as String?; isDir = true; break;
      case 'download_asset':
      case 'generate_image':
        raw = tc.args['save_path'] as String?; isDir = false; break;
      default: // write_file / edit_file / replace_in_file / read_file / search_text
        raw = tc.args['path'] as String?; isDir = false; break;
    }
    if (raw == null || raw.trim().isEmpty) return null; // no explicit path → uses default cwd
    final resolved = _resolvePath(raw, config);
    if (perms.isPathAllowed(resolved)) return null;
    return isDir ? resolved : p.dirname(resolved);
  }

  // Ask the user to grant access to a folder the agent wants but isn't allowed.
  // Returns true if granted (folder added to allowed folders), false if denied.
  Future<bool> _ensureAccess(ToolCall tc, AppConfig config, Future<bool> Function(ToolCall) requestApproval) async {
    final folder = _accessFolderNeeded(tc, config);
    if (folder == null) return true;
    final grant = ToolCall(id: _id(), name: '__grant_folder', args: {'folder': folder}, startedAt: DateTime.now());
    return requestApproval(grant);
  }

  String _resolvePath(String raw, AppConfig config) {
    final home = Platform.environment['HOME'] ?? '';
    if (raw.startsWith('~/')) return p.join(home, raw.substring(2));
    if (raw.startsWith('/')) return raw;
    final base = config.allowedFolders.isNotEmpty ? config.allowedFolders.first : Directory.current.path;
    return p.normalize(p.join(base, raw));
  }

  String? _dartRoot(String file) {
    var dir = File(file).parent;
    for (var i = 0; i < 7; i++) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  // Auto-verify: after the agent thinks it's done, run the analyzer on code it
  // edited this turn. Shows a visible tool card; returns error text to feed back
  // (so the model fixes it) or null if clean. Best-effort — silent if no toolchain.
  Future<String?> _autoVerify(AppConfig config, Set<String> editedAbs, ChatMessage assistant, void Function() onUpdate, bool Function()? isCancelled) async {
    final dartFiles = editedAbs.where((f) => f.toLowerCase().endsWith('.dart')).toList();
    final jsFiles = editedAbs.where((f) {
      final e = f.toLowerCase();
      return e.endsWith('.js') || e.endsWith('.mjs');
    }).toList();

    String? command;
    String? cwd;
    final flutter = EnvironmentService.tools['flutter'];
    final dart = EnvironmentService.tools['dart'];
    final node = EnvironmentService.tools['node'];

    if (dartFiles.isNotEmpty && (flutter != null || dart != null)) {
      // Use the project root (nearest pubspec) or just the edited file's dir —
      // both are guaranteed to exist (the file was just written).
      final root = _dartRoot(dartFiles.first) ?? File(dartFiles.first).parent.path;
      final hasPubspec = File(p.join(root, 'pubspec.yaml')).existsSync();
      final bin = (hasPubspec && flutter != null) ? flutter : (dart ?? flutter!);
      command = '$bin analyze 2>&1 | tail -60';
      cwd = root;
    } else if (jsFiles.isNotEmpty && node != null) {
      command = '${jsFiles.map((f) => '$node --check ${_shArg(f)}').join(' && ')} 2>&1';
      cwd = File(jsFiles.first).parent.path; // the edited file's dir always exists
    }
    if (command == null || cwd == null) return null;

    // Visible card so the user sees the auto-check happen.
    final tc = ToolCall(id: _id(), name: 'run_command', args: {'command': command.replaceAll(' 2>&1 | tail -60', '').replaceAll(' 2>&1', '')}, textAnchor: assistant.text.length, status: ToolStatus.running, startedAt: DateTime.now());
    assistant.toolCalls.add(tc);
    assistant.thinking = 'Avto-tekshiruv (analyze)…';
    onUpdate();

    final res = await executor.invoke('run_command', {'command': command, 'cwd': cwd}, isCancelled: isCancelled);
    final out = '${res.output ?? ''}${res.error ?? ''}';
    final clean = out.contains('No issues found') || out.trim().isEmpty;
    final hasErr = RegExp(r'error •|Error:|error:').hasMatch(out) && !clean;

    tc.result = ToolResult(ok: !hasErr, output: out.isEmpty ? 'No issues found.' : out, error: hasErr ? 'analyzer errors' : null);
    tc.status = hasErr ? ToolStatus.error : ToolStatus.done;
    tc.completedAt = DateTime.now();
    onUpdate();

    if (hasErr) {
      final clipped = out.length > 2500 ? '${out.substring(0, 2500)}\n…' : out;
      return 'AVTO-TEKSHIRUV xato topdi (siz tugatdim deyishdan oldin). Quyidagilarni tuzat va qaytadan tekshir:\n$clipped';
    }
    return null;
  }

  // Returns true when the agent should stop because it has failed too many rounds
  // in a row (prevents the costly infinite try-fail-retry loop).
  bool _tripFailureGuard(bool roundHadFailure, int Function() inc, void Function() reset, ChatMessage assistant) {
    if (!roundHadFailure) { reset(); return false; }
    final n = inc();
    if (n >= _maxConsecutiveFailures) {
      final note = '\n\n⚠️ $n urinishda ham xato bartaraf etilmadi. To‘xtatdim — iltimos qo‘shimcha yo‘nalish bering.';
      assistant.text += assistant.text.isEmpty ? note.trim() : note;
      return true;
    }
    return false;
  }

  void _compactGoogleHistory(List<gai.Content> history) {
    final fnIdx = <int>[];
    for (var i = 0; i < history.length; i++) {
      if (history[i].role == 'function') fnIdx.add(i);
    }
    if (fnIdx.length <= _keepFullToolRounds) return;
    final keepFrom = fnIdx[fnIdx.length - _keepFullToolRounds];
    for (var i = 0; i < keepFrom; i++) {
      final c = history[i];
      var changed = false;
      final newParts = <gai.Part>[];
      for (final part in c.parts) {
        if (part is gai.FunctionResponse) {
          final resp = Map<String, Object?>.from(part.response ?? const {});
          final out = resp['output'];
          if (out is String && out.length > _toolStubThreshold) {
            resp['output'] = '[omitted ${out.length} chars to save tokens]';
            changed = true;
          }
          newParts.add(gai.FunctionResponse(part.name, resp));
        } else {
          // Leave FunctionCall (and others) intact — reconstructing them would drop
          // the thought_signature 3.x needs.
          newParts.add(part);
        }
      }
      if (changed) history[i] = gai.Content(c.role, newParts);
    }
  }

  void _compactVertexHistory(List<fbai.Content> history) {
    final fnIdx = <int>[];
    for (var i = 0; i < history.length; i++) {
      if (history[i].role == 'function') fnIdx.add(i);
    }
    if (fnIdx.length <= _keepFullToolRounds) return;
    final keepFrom = fnIdx[fnIdx.length - _keepFullToolRounds];
    for (var i = 0; i < keepFrom; i++) {
      final c = history[i];
      var changed = false;
      final newParts = <fbai.Part>[];
      for (final part in c.parts) {
        if (part is fbai.FunctionResponse) {
          final resp = Map<String, Object?>.from(part.response);
          final out = resp['output'];
          if (out is String && out.length > _toolStubThreshold) {
            resp['output'] = '[omitted ${out.length} chars to save tokens]';
            changed = true;
          }
          newParts.add(fbai.FunctionResponse(part.name, resp));
        } else {
          // Leave FunctionCall (and others) intact — reconstructing them would drop
          // Gemini 3.x's thought_signature and break the next request.
          newParts.add(part);
        }
      }
      if (changed) history[i] = fbai.Content(c.role ?? 'model', newParts);
    }
  }

  // Gemini sometimes returns an empty candidate that firebase_ai/google_generative_ai
  // can't parse ("Unhandled format for Content: {}"). Retry once before giving up.
  // STREAMING: text deltas flow into the bubble live (like Claude). Returns the
  // turn's text + accumulated function calls; tokens are added to the running total.
  Future<({String text, List<gai.FunctionCall> calls})> _googleGen(gai.GenerativeModel model, List<gai.Content> history, ChatMessage assistant, void Function() onUpdate) async {
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      final buf = StringBuffer();
      final calls = <gai.FunctionCall>[];
      int? lp, lc, lt, lcache;
      var first = true;
      try {
        await for (final chunk in model.generateContentStream(history)) {
          final t = chunk.text;
          if (t != null && t.isNotEmpty) {
            if (first && assistant.text.isNotEmpty && !assistant.text.endsWith('\n')) assistant.text += '\n\n';
            first = false;
            assistant.text += t;
            buf.write(t);
            onUpdate();
          }
          for (final c in chunk.functionCalls) {
            calls.add(c);
          }
          final u = chunk.usageMetadata;
          if (u != null) { lp = u.promptTokenCount; lc = u.candidatesTokenCount; lt = u.totalTokenCount; lcache = _cachedOf(u); }
        }
        _accrueTokens(assistant, lp, lc, lt, lcache);
        onUpdate();
        return (text: buf.toString(), calls: calls);
      } catch (e) {
        if (buf.isNotEmpty || calls.isNotEmpty) { _accrueTokens(assistant, lp, lc, lt, lcache); return (text: buf.toString(), calls: calls); }
        lastErr = e;
        if (e.toString().contains('Unhandled format') && attempt == 0) continue;
        rethrow;
      }
    }
    throw lastErr!;
  }

  Future<({String text, List<fbai.FunctionCall> calls})> _vertexGen(fbai.GenerativeModel model, List<fbai.Content> history, ChatMessage assistant, void Function() onUpdate) async {
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      final buf = StringBuffer();
      final calls = <fbai.FunctionCall>[];
      int? lp, lc, lt, lcache;
      var first = true;
      try {
        await for (final chunk in model.generateContentStream(history)) {
          final t = chunk.text;
          if (t != null && t.isNotEmpty) {
            if (first && assistant.text.isNotEmpty && !assistant.text.endsWith('\n')) assistant.text += '\n\n';
            first = false;
            assistant.text += t;
            buf.write(t);
            onUpdate();
          }
          for (final c in chunk.functionCalls) {
            calls.add(c);
          }
          final u = chunk.usageMetadata;
          if (u != null) { lp = u.promptTokenCount; lc = u.candidatesTokenCount; lt = u.totalTokenCount; lcache = _cachedOf(u); }
        }
        _accrueTokens(assistant, lp, lc, lt, lcache);
        onUpdate();
        return (text: buf.toString(), calls: calls);
      } catch (e) {
        if (buf.isNotEmpty || calls.isNotEmpty) { _accrueTokens(assistant, lp, lc, lt, lcache); return (text: buf.toString(), calls: calls); }
        lastErr = e;
        if (e.toString().contains('Unhandled format') && attempt == 0) continue;
        rethrow;
      }
    }
    throw lastErr!;
  }

  // Vertex (firebase_ai) UsageMetadata has cachedContentTokenCount; the Google
  // SDK doesn't — read it tolerantly so both helpers can share one code path.
  int? _cachedOf(dynamic u) {
    try {
      return u.cachedContentTokenCount as int?;
    } catch (_) {
      return null;
    }
  }

  void _accrueTokens(ChatMessage assistant, int? prompt, int? cand, int? total, [int? cached]) {
    if (total == null) return;
    assistant.inputTokens += prompt ?? 0;
    assistant.outputTokens += cand ?? 0;
    assistant.totalTokens += total;
    assistant.cachedTokens += cached ?? 0;
    final thought = total - ((prompt ?? 0) + (cand ?? 0));
    if (thought > 0) assistant.thoughtTokens += thought;
  }

  // If the SDK still can't parse the response but we already did useful work,
  // end the turn cleanly instead of showing a scary red error.
  bool _isParseGlitch(Object e) => e.toString().contains('Unhandled format');

  Future<void> _runGoogleAiTurn(AppConfig config, String userText, List<ChatMessage> prior, ChatMessage assistant, void Function() onUpdate, Future<bool> Function(ToolCall) requestApproval, bool Function()? isCancelled, List<String> attachments) async {
    final history = <gai.Content>[];

    // TOKEN SAVER: Eski chat tarixidan asboblarning katta loglarini yashiramiz!
    for (final m in prior) {
      if (m.text.trim().isEmpty && m.toolCalls.isEmpty) continue;

      if (m.role == MessageRole.user) {
        history.add(gai.Content.text(m.text));
      } else if (m.role == MessageRole.model) {
        String content = m.text;
        if (m.toolCalls.isNotEmpty) {
          final summaries = m.toolCalls.map((tc) => "[Tool used: ${tc.name}]").join(', ');
          content += "\n\n$summaries";
        }
        if (content.trim().isNotEmpty) {
          history.add(gai.Content.model([gai.TextPart(content.trim())]));
        }
      }
    }

    final parts = <gai.Part>[gai.TextPart(userText)];
    for (final path in attachments) {
      try { final file = File(path); if (file.existsSync()) parts.add(gai.DataPart(_mimeForImage(path), file.readAsBytesSync())); } catch (_) {}
    }
    history.add(gai.Content('user', parts));

    final model = gai.GenerativeModel(
      model: config.activeModel,
      apiKey: config.googleApiKey,
      tools: [gai.Tool(functionDeclarations: buildGoogleAiTools())],
      systemInstruction: gai.Content.system(_getSystemPrompt(config)),
      generationConfig: gai.GenerationConfig(temperature: config.temperature),
    );

    assistant.thinking = 'Thinking...'; onUpdate();

    var iterations = 0;
    var consecutiveFailures = 0;
    final errorCounts = <String, int>{};
    final editedFiles = <String>{};
    var autoVerified = false;

    while (iterations++ < maxIterations) {
      if (isCancelled?.call() ?? false) { assistant.error = 'Stopped.'; onUpdate(); return; }
      _compactGoogleHistory(history);

      String streamedText;
      List<gai.FunctionCall> calls;
      try {
        final r = await _googleGen(model, history, assistant, onUpdate);
        streamedText = r.text;
        calls = r.calls;
      } catch (e) {
        assistant.thinking = null;
        if (_isParseGlitch(e) && (assistant.text.trim().isNotEmpty || assistant.toolCalls.isNotEmpty)) { onUpdate(); return; }
        assistant.error = e.toString(); onUpdate(); return;
      }

      // text already streamed live into assistant.text
      if (calls.isEmpty) {
        if (!autoVerified && editedFiles.isNotEmpty && !(isCancelled?.call() ?? false)) {
          autoVerified = true;
          final errs = await _autoVerify(config, editedFiles, assistant, onUpdate, isCancelled);
          if (errs != null) { history.add(gai.Content.text(errs)); assistant.thinking = 'Xatolarni tuzatyapman…'; onUpdate(); continue; }
        }
        break; // AI o'zi hamma ishni qilib tugatdi.
      }

      final executedTools = <ToolCall>[];
      for (final call in calls) {
        if (isCancelled?.call() ?? false) break;
        final tc = ToolCall(id: _id(), name: call.name, args: Map<String, Object?>.from(call.args), textAnchor: assistant.text.length, startedAt: DateTime.now());
        assistant.toolCalls.add(tc); assistant.thinking = tc.summary; onUpdate();
        executedTools.add(tc);

        if (!await _ensureAccess(tc, config, requestApproval)) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'Folder access denied.'); onUpdate();
          continue;
        }

        bool approved = !(executor.supportsLocalTools && tc.isMutating && perms.requiresApproval(tc.name, tc.ruleSignature)) || await (() { tc.status = ToolStatus.pending; onUpdate(); return requestApproval(tc); })();
        if (!approved) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'Denied.'); onUpdate();
          continue;
        }
        tc.status = ToolStatus.running; onUpdate();
        final raw = await executor.invoke(tc.name, tc.args, isCancelled: isCancelled);
        tc.result = ToolResult(ok: raw.ok, error: raw.error, output: raw.output);
        tc.status = tc.result!.ok ? ToolStatus.done : ToolStatus.error; tc.completedAt = DateTime.now(); onUpdate();
      }

      for (final tc in executedTools) {
        if (tc.result?.ok == true && _isFileEditTool(tc.name) && tc.args['path'] is String) {
          editedFiles.add(_resolvePath(tc.args['path'] as String, config));
          autoVerified = false;
        }
      }

      assistant.thinking = 'Thinking...'; onUpdate();

      // Keep ORIGINAL FunctionCall objects (preserve thought_signature for 3.x).
      history.add(gai.Content.model([
        if (streamedText.isNotEmpty) gai.TextPart(streamedText),
        ...calls,
      ]));

      history.add(gai.Content('function', [
        ...executedTools.map((tc) => gai.FunctionResponse(tc.name, {
          'ok': tc.result!.ok,
          if (tc.result!.output != null) 'output': tc.result!.output,
          if (tc.result!.error != null) 'error': tc.result!.error
        }))
      ]));

      if (_trackStuck(errorCounts, executedTools).isNotEmpty) {
        assistant.text += '\n\n⚠️ Bir xil xato $_maxSameError marta takrorlandi — to‘xtatdim. Boshqacha yondashuv bering.';
        break;
      }
      if (_tripFailureGuard(executedTools.any((tc) => tc.result != null && !tc.result!.ok), () => ++consecutiveFailures, () => consecutiveFailures = 0, assistant)) break;
    }
    assistant.thinking = null; onUpdate();
  }

  Future<void> _runVertexTurn(AppConfig config, String userText, List<ChatMessage> prior, ChatMessage assistant, void Function() onUpdate, Future<bool> Function(ToolCall) requestApproval, bool Function()? isCancelled, List<String> attachments) async {
    final history = <fbai.Content>[];

    // TOKEN SAVER
    for (final m in prior) {
      if (m.text.trim().isEmpty && m.toolCalls.isEmpty) continue;

      if (m.role == MessageRole.user) {
        history.add(fbai.Content.text(m.text));
      } else if (m.role == MessageRole.model) {
        String content = m.text;
        if (m.toolCalls.isNotEmpty) {
          final summaries = m.toolCalls.map((tc) => "[Tool used: ${tc.name}]").join(', ');
          content += "\n\n$summaries";
        }
        if (content.trim().isNotEmpty) {
          history.add(fbai.Content.model([fbai.TextPart(content.trim())]));
        }
      }
    }

    final parts = <fbai.Part>[fbai.TextPart(userText)];
    for (final path in attachments) {
      try { final file = File(path); if (file.existsSync()) parts.add(fbai.InlineDataPart(_mimeForImage(path), file.readAsBytesSync())); } catch (_) {}
    }
    history.add(fbai.Content('user', parts));

    // Preview/Gemini-3.x models live on the Vertex `global` endpoint; 2.5 models
    // use the default region. Pick the right location so the model resolves.
    final loc = (config.activeModel.startsWith('gemini-3') || config.activeModel.contains('preview')) ? 'global' : null;
    final model = fbai.FirebaseAI.vertexAI(location: loc).generativeModel(
      model: config.activeModel,
      tools: [fbai.Tool.functionDeclarations(buildVertexTools())],
      systemInstruction: fbai.Content.system(_getSystemPrompt(config)),
      generationConfig: fbai.GenerationConfig(temperature: config.temperature),
    );

    assistant.thinking = 'Thinking...'; onUpdate();

    var iterations = 0;
    var consecutiveFailures = 0;
    final errorCounts = <String, int>{};
    final editedFiles = <String>{};
    var autoVerified = false;

    while (iterations++ < maxIterations) {
      if (isCancelled?.call() ?? false) { assistant.error = 'Stopped.'; onUpdate(); return; }
      _compactVertexHistory(history);

      String streamedText;
      List<fbai.FunctionCall> calls;
      try {
        final r = await _vertexGen(model, history, assistant, onUpdate);
        streamedText = r.text;
        calls = r.calls;
      } catch (e) {
        assistant.thinking = null;
        if (_isParseGlitch(e) && (assistant.text.trim().isNotEmpty || assistant.toolCalls.isNotEmpty)) { onUpdate(); return; }
        assistant.error = e.toString(); onUpdate(); return;
      }

      // text already streamed live into assistant.text
      if (calls.isEmpty) {
        if (!autoVerified && editedFiles.isNotEmpty && !(isCancelled?.call() ?? false)) {
          autoVerified = true;
          final errs = await _autoVerify(config, editedFiles, assistant, onUpdate, isCancelled);
          if (errs != null) { history.add(fbai.Content.text(errs)); assistant.thinking = 'Xatolarni tuzatyapman…'; onUpdate(); continue; }
        }
        break; // AI ishlarni bitirsa toxtaydi
      }

      final executedTools = <ToolCall>[];
      for (final call in calls) {
        if (isCancelled?.call() ?? false) break;
        final tc = ToolCall(id: _id(), name: call.name, args: Map<String, Object?>.from(call.args), textAnchor: assistant.text.length, startedAt: DateTime.now());
        assistant.toolCalls.add(tc); assistant.thinking = tc.summary; onUpdate();
        executedTools.add(tc);

        if (!await _ensureAccess(tc, config, requestApproval)) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'Folder access denied.'); onUpdate();
          continue;
        }

        bool approved = !(executor.supportsLocalTools && tc.isMutating && perms.requiresApproval(tc.name, tc.ruleSignature)) || await (() { tc.status = ToolStatus.pending; onUpdate(); return requestApproval(tc); })();
        if (!approved) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'Denied.'); onUpdate();
          continue;
        }
        tc.status = ToolStatus.running; onUpdate();
        final raw = await executor.invoke(tc.name, tc.args, isCancelled: isCancelled);
        tc.result = ToolResult(ok: raw.ok, error: raw.error, output: raw.output);
        tc.status = tc.result!.ok ? ToolStatus.done : ToolStatus.error; tc.completedAt = DateTime.now(); onUpdate();
      }

      for (final tc in executedTools) {
        if (tc.result?.ok == true && _isFileEditTool(tc.name) && tc.args['path'] is String) {
          editedFiles.add(_resolvePath(tc.args['path'] as String, config));
          autoVerified = false;
        }
      }

      assistant.thinking = 'Thinking...'; onUpdate();

      // Keep the ORIGINAL FunctionCall objects — they carry Gemini 3.x's
      // thought_signature, which must be echoed back or the next request is rejected.
      history.add(fbai.Content.model([
        if (streamedText.isNotEmpty) fbai.TextPart(streamedText),
        ...calls,
      ]));

      history.add(fbai.Content('function', [
        ...executedTools.map((tc) => fbai.FunctionResponse(tc.name, {
          'ok': tc.result!.ok,
          if (tc.result!.output != null) 'output': tc.result!.output,
          if (tc.result!.error != null) 'error': tc.result!.error
        }))
      ]));

      if (_trackStuck(errorCounts, executedTools).isNotEmpty) {
        assistant.text += '\n\n⚠️ Bir xil xato $_maxSameError marta takrorlandi — to‘xtatdim. Boshqacha yondashuv bering.';
        break;
      }
      if (_tripFailureGuard(executedTools.any((tc) => tc.result != null && !tc.result!.ok), () => ++consecutiveFailures, () => consecutiveFailures = 0, assistant)) break;
    }
    assistant.thinking = null; onUpdate();
  }
}