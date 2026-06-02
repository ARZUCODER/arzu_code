import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/process_manager.dart';
import '../../theme/app_theme.dart';

class TerminalPanel extends StatefulWidget {
  final VoidCallback onClose;
  const TerminalPanel({super.key, required this.onClose});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  String? _selectedId;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ProcessManager.instance.revision,
      builder: (context, _, __) {
        final procs = ProcessManager.instance.processes;
        ManagedProcess? selected;
        if (procs.isNotEmpty) {
          selected = procs.firstWhere((p) => p.id == _selectedId, orElse: () => procs.last);
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });

        return Container(
          height: 240,
          decoration: const BoxDecoration(color: Color(0xFF121110), border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(
            children: [
              _header(procs),
              if (procs.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No background processes.\nThe agent starts servers (flutter run, npm start) here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textFaint, height: 1.5),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      _tabs(procs, selected),
                      Expanded(child: _output(selected)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(List<ManagedProcess> procs) {
    final running = procs.where((p) => p.running).length;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
      child: Row(
        children: [
          const Icon(LucideIcons.terminal, size: 14, color: AppColors.textDim),
          const SizedBox(width: 8),
          Text('TERMINALS', style: AppTheme.mono(size: 11, color: AppColors.textDim, weight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('$running running · ${procs.length} total', style: AppTheme.mono(size: 10.5, color: AppColors.textFaint)),
          const Spacer(),
          _headerBtn(LucideIcons.trash_2, 'Clear finished', () => ProcessManager.instance.clearFinished()),
          const SizedBox(width: 4),
          _headerBtn(LucideIcons.chevron_down, 'Hide panel', widget.onClose),
        ],
      ),
    );
  }

  Widget _headerBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: AppColors.textFaint),
        ),
      ),
    );
  }

  Widget _tabs(List<ManagedProcess> procs, ManagedProcess? selected) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        children: [
          for (final pr in procs) Padding(padding: const EdgeInsets.only(right: 6), child: _tab(pr, pr.id == selected?.id)),
        ],
      ),
    );
  }

  Widget _tab(ManagedProcess pr, bool selected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedId = pr.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: selected ? AppColors.surfaceHigh : AppColors.surface, borderRadius: BorderRadius.circular(7), border: Border.all(color: selected ? AppColors.border : AppColors.borderSubtle)),
        child: Row(
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: pr.running ? AppColors.green : AppColors.textFaint)),
            const SizedBox(width: 7),
            Text('${pr.id} · ${pr.label}', style: AppTheme.mono(size: 11, color: selected ? AppColors.text : AppColors.textDim)),
            const SizedBox(width: 8),
            if (pr.running)
              GestureDetector(onTap: () => ProcessManager.instance.stop(pr.id), child: const Icon(LucideIcons.square, size: 11, color: AppColors.red))
            else
              GestureDetector(onTap: () => ProcessManager.instance.remove(pr.id), child: const Icon(LucideIcons.x, size: 12, color: AppColors.textFaint)),
          ],
        ),
      ),
    );
  }

  Widget _output(ManagedProcess? pr) {
    if (pr == null) return const SizedBox.shrink();
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: SelectableText(
          pr.output.toString().isEmpty ? '(no output yet)' : pr.output.toString(),
          style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: AppColors.textDim, height: 1.45),
        ),
      ),
    );
  }
}