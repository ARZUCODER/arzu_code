import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../providers/chat_provider.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import 'file_explorer.dart';

class Sidebar extends ConsumerStatefulWidget {
  final VoidCallback onOpenSettings;
  const Sidebar({super.key, required this.onOpenSettings});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  bool _filesView = false;

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final config = ref.watch(configControllerProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(right: BorderSide(color: AppColors.borderSubtle, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(7)),
                  child: const Icon(LucideIcons.asterisk, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('Arzu Code', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.text)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _SegToggle(filesView: _filesView, onChanged: (v) => setState(() => _filesView = v)),
          ),
          const SizedBox(height: 10),
          if (!_filesView) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _NewSessionButton(onTap: controller.newSession),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 16, 6),
              child: Text('SESSIONS', style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: AppColors.textFaint)),
            ),
            Expanded(
              child: chat.sessions.isEmpty
                  ? const _EmptySessions()
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: chat.sessions.length,
                itemBuilder: (_, i) {
                  final s = chat.sessions[i];
                  return _SessionTile(
                    title: s.title,
                    selected: s.id == chat.activeId,
                    onTap: () => controller.selectSession(s.id),
                    onDelete: () => controller.deleteSession(s.id),
                  );
                },
              ),
            ),
          ] else
            const Expanded(child: FileExplorer()),
          const Divider(height: 1, color: AppColors.borderSubtle),
          _FolderSummary(count: config.allowedFolders.length, onTap: widget.onOpenSettings),
        ],
      ),
    );
  }
}

class _SegToggle extends StatelessWidget {
  final bool filesView;
  final ValueChanged<bool> onChanged;
  const _SegToggle({required this.filesView, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          _seg(LucideIcons.message_square, 'Chats', !filesView, () => onChanged(false)),
          _seg(LucideIcons.folder_tree, 'Files', filesView, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _seg(IconData icon, String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: selected ? AppColors.surfaceHigh : Colors.transparent, borderRadius: BorderRadius.circular(7)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: selected ? AppColors.accent : AppColors.textFaint),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? AppColors.text : AppColors.textFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewSessionButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NewSessionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: const Row(
            children: [
              Icon(LucideIcons.plus, size: 16, color: AppColors.accent),
              SizedBox(width: 8),
              Text('New session', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatefulWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _SessionTile({required this.title, required this.selected, required this.onTap, required this.onDelete});

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: widget.selected ? AppColors.surfaceHigh : (_hover ? AppColors.surface : Colors.transparent), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Icon(LucideIcons.message_square, size: 14, color: widget.selected ? AppColors.accent : AppColors.textFaint),
              const SizedBox(width: 9),
              Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: widget.selected ? AppColors.text : AppColors.textDim))),
              if (_hover || widget.selected) GestureDetector(onTap: widget.onDelete, child: const Icon(LucideIcons.trash_2, size: 13, color: AppColors.textFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No sessions yet.\nStart a new one above.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textFaint)),
      ),
    );
  }
}

class _FolderSummary extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _FolderSummary({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(LucideIcons.folder_lock, size: 15, color: AppColors.textDim),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                count == 0 ? 'No allowed folders' : '$count allowed folder${count == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12.5, color: count == 0 ? AppColors.yellow : AppColors.textDim),
              ),
            ),
            const Icon(LucideIcons.settings, size: 15, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

String shortenPath(String path) {
  final home = p.split(path);
  if (home.length > 3) return '…/${home.sublist(home.length - 2).join('/')}';
  return path;
}