import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/tool_call.dart';
import '../../theme/app_theme.dart';

class ToolCallCard extends StatefulWidget {
  final ToolCall call;
  const ToolCallCard({super.key, required this.call});

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  IconData get _icon => switch (widget.call.name) {
    'semantic_search' => LucideIcons.brain_circuit,
    'read_file' => LucideIcons.file_text,
    'write_file' => LucideIcons.file_plus,
    'edit_file' => LucideIcons.file_pen,
    'make_dir' => LucideIcons.folder_plus,
    'list_dir' => LucideIcons.folder_open,
    'path_exists' => LucideIcons.search,
    'search_text' => LucideIcons.search,
    'run_command' => LucideIcons.terminal,
    'create_project' => LucideIcons.box,
    'file_tree' => LucideIcons.list_tree,
    'download_asset' => LucideIcons.download,
    'generate_image' => LucideIcons.image,
    'start_background_process' => LucideIcons.play,
    'read_process_output' => LucideIcons.scroll_text,
    'list_processes' => LucideIcons.list,
    'stop_process' => LucideIcons.square,
    _ => LucideIcons.wrench,
  };

  Color get _statusColor => switch (widget.call.status) {
    ToolStatus.pending => AppColors.yellow,
    ToolStatus.approved => AppColors.blue,
    ToolStatus.running => AppColors.blue,
    ToolStatus.done => AppColors.green,
    ToolStatus.error => AppColors.red,
    ToolStatus.denied => AppColors.textFaint,
  };

  Widget _statusWidget() {
    switch (widget.call.status) {
      case ToolStatus.running:
        return const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.blue));
      case ToolStatus.done:
        return Icon(LucideIcons.check, size: 14, color: _statusColor);
      case ToolStatus.error:
        return Icon(LucideIcons.x, size: 14, color: _statusColor);
      case ToolStatus.denied:
        return Icon(LucideIcons.ban, size: 13, color: _statusColor);
      case ToolStatus.pending:
        return Icon(LucideIcons.clock, size: 13, color: _statusColor);
      case ToolStatus.approved:
        return Icon(LucideIcons.check, size: 13, color: _statusColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final hasOutput = call.result != null && (call.result!.output != null || call.result!.error != null);

    final end = call.completedAt ?? DateTime.now();
    final sec = (end.difference(call.startedAt).inMilliseconds / 1000).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasOutput ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(_icon, size: 14, color: AppColors.textDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      call.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(size: 11.5, color: AppColors.text, height: 1.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${sec}s', style: AppTheme.mono(size: 10, color: AppColors.textFaint)),
                  const SizedBox(width: 8),
                  _statusWidget(),
                  if (hasOutput) ...[
                    const SizedBox(width: 6),
                    Icon(_expanded ? LucideIcons.chevron_up : LucideIcons.chevron_down, size: 14, color: AppColors.textFaint),
                  ],
                ],
              ),
            ),
          ),
          if (call.name == 'write_file' && !_expanded) _ContentPreview(content: call.args['content'] as String? ?? ''),
          if (_expanded && hasOutput)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: const BoxDecoration(color: Color(0xFF121110), border: Border(top: BorderSide(color: AppColors.borderSubtle))),
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    call.result!.display,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.0,
                      color: call.result!.ok ? AppColors.textDim : AppColors.red,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContentPreview extends StatelessWidget {
  final String content;
  const _ContentPreview({required this.content});

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final preview = lines.take(4).join('\n');
    final more = lines.length > 4 ? '\n  … +${lines.length - 4} lines' : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF12211A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.15)),
        ),
        child: Text(
          preview + more,
          style: AppTheme.mono(size: 10, color: AppColors.green, height: 1.4),
        ),
      ),
    );
  }
}