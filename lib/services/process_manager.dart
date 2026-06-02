import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A long-running background process started by the agent (e.g. `flutter run`,
/// `npm start`). Its stdout/stderr are streamed into [output] so the UI and the
/// agent can read the live log without blocking the chat turn.
class ManagedProcess {
  final String id;
  final String label;
  final String command;
  final String cwd;
  final Process process;
  final DateTime startedAt;

  final StringBuffer output = StringBuffer();
  int? exitCode;
  bool get running => exitCode == null;

  ManagedProcess({
    required this.id,
    required this.label,
    required this.command,
    required this.cwd,
    required this.process,
    required this.startedAt,
  });

  String tail({int maxChars = 4000}) {
    final s = output.toString();
    if (s.length <= maxChars) return s;
    return '…(truncated)…\n${s.substring(s.length - maxChars)}';
  }
}

/// Global registry of background processes. Lives for the whole app session so
/// the bottom terminal panel and the agent tools share the same state.
class ProcessManager {
  ProcessManager._();
  static final ProcessManager instance = ProcessManager._();

  final List<ManagedProcess> _processes = [];
  int _counter = 0;

  /// Bumped whenever anything changes so the UI can rebuild.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<ManagedProcess> get processes => List.unmodifiable(_processes);

  ManagedProcess? byId(String id) {
    for (final p in _processes) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _bump() => revision.value++;

  Future<ManagedProcess> start({
    required String command,
    required String cwd,
    String? label,
  }) async {
    final process = await Process.start('/bin/zsh', ['-lc', command],
        workingDirectory: cwd);
    final id = 'bg${++_counter}';
    final mp = ManagedProcess(
      id: id,
      label: label ?? command.split(RegExp(r'\s+')).take(3).join(' '),
      command: command,
      cwd: cwd,
      process: process,
      startedAt: DateTime.now(),
    );
    _processes.add(mp);

    void append(String chunk) {
      mp.output.write(chunk);
      // Keep the buffer bounded so very chatty processes don't grow forever.
      if (mp.output.length > 200000) {
        final s = mp.output.toString();
        mp.output
          ..clear()
          ..write(s.substring(s.length - 120000));
      }
      _bump();
    }

    process.stdout.listen((d) => append(String.fromCharCodes(d)));
    process.stderr.listen((d) => append(String.fromCharCodes(d)));
    process.exitCode.then((code) {
      mp.exitCode = code;
      mp.output.write('\n[process exited with code $code]\n');
      _bump();
    });

    _bump();
    return mp;
  }

  bool stop(String id) {
    final mp = byId(id);
    if (mp == null || !mp.running) return false;
    try {
      mp.process.kill(ProcessSignal.sigkill);
    } catch (_) {}
    return true;
  }

  void remove(String id) {
    final mp = byId(id);
    if (mp == null) return;
    if (mp.running) {
      try {
        mp.process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _processes.removeWhere((p) => p.id == id);
    _bump();
  }

  void clearFinished() {
    _processes.removeWhere((p) => !p.running);
    _bump();
  }
}
