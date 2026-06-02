import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_provider.dart';
import '../services/export_service.dart';
import '../services/process_manager.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import 'widgets/chat_panel.dart';
import 'widgets/selectors.dart';
import 'widgets/sidebar.dart';
import 'widgets/terminal_panel.dart';
import 'widgets/folder_to_txt_dialog.dart';
import '../models/chat_message.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _sidebarOpen = true;
  bool _terminalOpen = false;

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SettingsScreen(),
    ));
  }

  void _openFolderToTxt() {
    showFolderToTxtDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgGradTop, AppColors.bg],
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: _sidebarOpen ? 264 : 0,
              child: _sidebarOpen
                  ? Sidebar(onOpenSettings: _openSettings)
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    sidebarOpen: _sidebarOpen,
                    terminalOpen: _terminalOpen,
                    onToggleSidebar: () => setState(() => _sidebarOpen = !_sidebarOpen),
                    onToggleTerminal: () => setState(() => _terminalOpen = !_terminalOpen),
                    onOpenSettings: _openSettings,
                    onOpenFolderToTxt: _openFolderToTxt,
                  ),
                  const Expanded(child: ChatPanel()),
                  if (_terminalOpen)
                    TerminalPanel(
                      onClose: () => setState(() => _terminalOpen = false),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final bool sidebarOpen;
  final bool terminalOpen;
  final VoidCallback onToggleSidebar;
  final VoidCallback onToggleTerminal;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenFolderToTxt;

  const _TopBar({
    required this.sidebarOpen,
    required this.terminalOpen,
    required this.onToggleSidebar,
    required this.onToggleTerminal,
    required this.onOpenSettings,
    required this.onOpenFolderToTxt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    final title = chat.active?.title ?? 'Arzu Code';

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          _iconButton(
            sidebarOpen ? LucideIcons.panel_left_close : LucideIcons.panel_left,
            onToggleSidebar,
            tooltip: 'Toggle sidebar',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Flexible(
            flex: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 8),
                  const _TokenBadge(),
                  const SizedBox(width: 8),
                  const ModelSelector(),
                  const SizedBox(width: 8),
                  const ModeSelector(),
                  const SizedBox(width: 8),
                  _terminalButton(),
                  const SizedBox(width: 4),
                  _iconButton(LucideIcons.folder_input, onOpenFolderToTxt, tooltip: 'Folder to TXT'),
                  const SizedBox(width: 4),
                  _iconButton(
                    LucideIcons.download,
                        () {
                      if (chat.active != null) {
                        ExportService.exportSessionAsMarkdown(chat.active!);
                      }
                    },
                    tooltip: 'Export as Markdown',
                  ),
                  const SizedBox(width: 4),
                  _iconButton(LucideIcons.settings, onOpenSettings, tooltip: 'Settings'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _terminalButton() {
    return ValueListenableBuilder<int>(
      valueListenable: ProcessManager.instance.revision,
      builder: (context, _, __) {
        final running = ProcessManager.instance.processes.where((p) => p.running).length;
        return Tooltip(
          message: 'Terminals',
          child: InkWell(
            onTap: onToggleTerminal,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(LucideIcons.terminal, size: 18, color: terminalOpen ? AppColors.accent : AppColors.textDim),
                  if (running > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text('$running',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 8.5, color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {String? tooltip}) {
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 18, color: AppColors.textDim),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }
}

class _TokenBadge extends ConsumerWidget {
  const _TokenBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    if (chat.active == null) return const SizedBox.shrink();

    final session = chat.active!;
    final total = session.totalTokens;
    if (total == 0) return const SizedBox.shrink();

    // Oxirgi AI dan kelgan xabarni ajratib olish (Oxirgi So'rov)
    final modelMsgs = session.messages.where((m) => m.role == MessageRole.model).toList();
    final lastMsg = modelMsgs.isNotEmpty ? modelMsgs.last : null;

    final msgIn = lastMsg?.inputTokens ?? 0;
    final msgOut = lastMsg?.outputTokens ?? 0;
    final msgTh = lastMsg?.thoughtTokens ?? 0;
    final msgTot = lastMsg?.totalTokens ?? 0;

    final tooltip = '''
⚡ LAST REQUEST
Total: $msgTot
Input: $msgIn
Output: $msgOut
Thinking: $msgTh

📦 SESSION TOTAL
Total: $total
Input: ${session.totalInputTokens}
Output: ${session.totalOutputTokens}
Thinking: ${session.totalThoughtTokens}

* Note: ~1.5k input tokens are System Rules & Tools sent every time.
'''.trim();

    return Tooltip(
      message: tooltip,
      textAlign: TextAlign.left,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.coins, size: 13, color: AppColors.yellow),
            const SizedBox(width: 6),
            Text(
                '${_format(msgTot)} / ${_format(total)}',
                style: AppTheme.mono(size: 11.5, color: AppColors.textDim, weight: FontWeight.w600)
            ),
          ],
        ),
      ),
    );
  }

  String _format(int n) {
    if (n < 1000) return n.toString();
    return '${(n / 1000).toStringAsFixed(1)}k';
  }
}