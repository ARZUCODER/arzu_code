import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../theme/app_theme.dart';

/// A real, interactive terminal embedded in the app (PTY + xterm). Lets you run
/// full TUI programs like `claude` or `ollama launch claude --model …` right
/// inside Arzu Code, exactly like a system terminal.
class PtyTerminal extends StatefulWidget {
  /// Optional command typed automatically once the shell is ready.
  final String? initialCommand;
  final String? cwd;
  const PtyTerminal({super.key, this.initialCommand, this.cwd});

  @override
  State<PtyTerminal> createState() => _PtyTerminalState();
}

class _PtyTerminalState extends State<PtyTerminal> {
  final terminal = Terminal(maxLines: 12000);
  Pty? _pty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    final home = Platform.environment['HOME'] ?? '';
    // Use a working dir that actually exists (stale folder → spawn failure).
    var cwd = widget.cwd ?? home;
    if (cwd.isEmpty || !Directory(cwd).existsSync()) {
      cwd = (home.isNotEmpty && Directory(home).existsSync()) ? home : Directory.current.path;
    }
    // Solid PATH so ollama/claude/flutter resolve even when launched from /Applications.
    final env = Map<String, String>.from(Platform.environment);
    final paths = <String>{
      '/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin', '/usr/sbin', '/sbin',
      if (home.isNotEmpty) '$home/.local/bin',
      ...(env['PATH'] ?? '').split(':').where((p) => p.isNotEmpty),
    };
    env['PATH'] = paths.join(':');
    final pty = Pty.start(
      shell,
      arguments: ['-l'],
      workingDirectory: cwd,
      environment: env,
      rows: terminal.viewHeight,
      columns: terminal.viewWidth,
    );
    _pty = pty;

    pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(terminal.write);
    pty.exitCode.then((code) {
      if (mounted) terminal.write('\r\n\x1b[90m[shell exited: $code]\x1b[0m\r\n');
    });

    terminal.onOutput = (data) => pty.write(const Utf8Encoder().convert(data));
    terminal.onResize = (w, h, pw, ph) => pty.resize(h, w);

    final cmd = widget.initialCommand;
    if (cmd != null && cmd.trim().isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 600), () {
        pty.write(const Utf8Encoder().convert('$cmd\r'));
      });
    }
  }

  @override
  void dispose() {
    try {
      _pty?.kill();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0D0C),
      child: TerminalView(
        terminal,
        autofocus: true,
        backgroundOpacity: 0,
        padding: const EdgeInsets.all(10),
        theme: _arzuTerminalTheme,
        textStyle: const TerminalStyle(fontSize: 12.5, fontFamily: 'monospace'),
      ),
    );
  }
}

// Warm-dark palette matching the app.
const _arzuTerminalTheme = TerminalTheme(
  cursor: AppColors.accent,
  selection: Color(0x55E8915B),
  foreground: Color(0xFFE7E2DA),
  background: Color(0xFF0E0D0C),
  black: Color(0xFF2A2724),
  red: Color(0xFFE5694B),
  green: Color(0xFF7FB069),
  yellow: Color(0xFFE0B341),
  blue: Color(0xFF6CA0DC),
  magenta: Color(0xFFB48EAD),
  cyan: Color(0xFF66C2C2),
  white: Color(0xFFE7E2DA),
  brightBlack: Color(0xFF6B645C),
  brightRed: Color(0xFFE5694B),
  brightGreen: Color(0xFF8FCB77),
  brightYellow: Color(0xFFE8915B),
  brightBlue: Color(0xFF7FB0E8),
  brightMagenta: Color(0xFFC9A8C4),
  brightCyan: Color(0xFF7FD6D6),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFE0B341),
  searchHitBackgroundCurrent: Color(0xFFE8915B),
  searchHitForeground: Color(0xFF0E0D0C),
);
