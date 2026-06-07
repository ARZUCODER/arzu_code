import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../theme/app_theme.dart';
import 'pty_terminal.dart';

/// Opens a large embedded terminal dialog. Optionally auto-runs [command]
/// (e.g. `ollama launch claude --model qwen3-coder:480b-cloud`).
Future<void> showClaudeCli(BuildContext context, {String? command, String? cwd, String title = 'Terminal'}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _ClaudeCliDialog(command: command, cwd: cwd, title: title),
  );
}

class _ClaudeCliDialog extends StatelessWidget {
  final String? command;
  final String? cwd;
  final String title;
  const _ClaudeCliDialog({this.command, this.cwd, required this.title});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        width: size.width * 0.82,
        height: size.height * 0.82,
        decoration: BoxDecoration(
          color: const Color(0xFF0E0D0C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Title bar.
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.square_terminal, size: 15, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                  const Spacer(),
                  if (command != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(command!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTheme.mono(size: 11, color: AppColors.textFaint)),
                    ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(padding: EdgeInsets.all(5), child: Icon(LucideIcons.x, size: 16, color: AppColors.textDim)),
                  ),
                ],
              ),
            ),
            // Live PTY terminal. Keyed by command so each launch is a fresh shell.
            Expanded(
              child: PtyTerminal(key: ValueKey(command ?? 'shell'), initialCommand: command, cwd: cwd),
            ),
          ],
        ),
      ),
    );
  }
}
