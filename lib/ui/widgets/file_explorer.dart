import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';

const _explorerIgnored = {
  '.git', 'node_modules', 'build', 'dist', '.dart_tool', '.pub-cache',
  '.idea', '.gradle', 'Pods', '.next', '.venv', '__pycache__', '.DS_Store',
};

class FileExplorer extends ConsumerStatefulWidget {
  const FileExplorer({super.key});

  @override
  ConsumerState<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends ConsumerState<FileExplorer> {
  bool _dragging = false;
  int _refreshKey = 0;

  void _handleDrop(List<String> paths) {
    final notifier = ref.read(configControllerProvider.notifier);
    for (final path in paths) {
      final dir = Directory(path).existsSync() ? path : p.dirname(path);
      notifier.addFolder(dir);
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(configControllerProvider).allowedFolders;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        _handleDrop(detail.files.map((f) => f.path).toList());
      },
      child: Container(
        decoration: BoxDecoration(
          border: _dragging ? Border.all(color: AppColors.accent, width: 1.5) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 10, 6),
              child: Row(
                children: [
                  const Text('WORKSPACE', style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: AppColors.textFaint)),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _refreshKey++),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(LucideIcons.refresh_cw, size: 13, color: AppColors.textFaint),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: folders.isEmpty
                  ? const _EmptyExplorer()
                  : ListView(
                key: ValueKey(_refreshKey),
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                children: [
                  for (final folder in folders) _DirNode(path: folder, depth: 0, isRoot: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyExplorer extends StatelessWidget {
  const _EmptyExplorer();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'No folders yet.\nDrag a folder here, or add one\nin Settings → Allowed folders.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.5),
        ),
      ),
    );
  }
}

class _DirNode extends StatefulWidget {
  final String path;
  final int depth;
  final bool isRoot;
  const _DirNode({required this.path, required this.depth, this.isRoot = false});

  @override
  State<_DirNode> createState() => _DirNodeState();
}

class _DirNodeState extends State<_DirNode> {
  bool _expanded = false;
  List<FileSystemEntity>? _children;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _children == null) _load();
  }

  void _load() {
    try {
      final entries = Directory(widget.path).listSync()..removeWhere((e) => _explorerIgnored.contains(p.basename(e.path)));
      entries.sort((a, b) {
        final ad = a is Directory ? 0 : 1;
        final bd = b is Directory ? 0 : 1;
        if (ad != bd) return ad - bd;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      setState(() => _children = entries);
    } catch (_) {
      setState(() => _children = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(widget.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          depth: widget.depth,
          icon: _expanded ? LucideIcons.folder_open : LucideIcons.folder,
          iconColor: AppColors.accent,
          label: name.isEmpty ? widget.path : name,
          bold: widget.isRoot,
          leading: Icon(
            _expanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
            size: 13,
            color: AppColors.textFaint,
          ),
          onTap: _toggle,
        ),
        if (_expanded && _children != null)
          for (final e in _children!)
            if (e is Directory) _DirNode(path: e.path, depth: widget.depth + 1)
            else _FileTile(path: e.path, depth: widget.depth + 1),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  final String path;
  final int depth;
  const _FileTile({required this.path, required this.depth});

  IconData get _icon {
    switch (p.extension(path).toLowerCase()) {
      case '.dart': return LucideIcons.code;
      case '.png': case '.jpg': case '.jpeg': case '.gif': case '.webp': return LucideIcons.image;
      case '.json': case '.yaml': case '.yml': return LucideIcons.braces;
      case '.md': return LucideIcons.file_text;
      default: return LucideIcons.file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Row(
      depth: depth,
      icon: _icon,
      iconColor: AppColors.textDim,
      label: p.basename(path),
      onTap: () {
        Clipboard.setData(ClipboardData(text: path));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.surfaceHigh,
            content: Text('Copied path: ${p.basename(path)}', style: const TextStyle(color: AppColors.text, fontSize: 12.5)),
          ),
        );
      },
    );
  }
}

class _Row extends StatefulWidget {
  final int depth;
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool bold;
  final Widget? leading;
  final VoidCallback onTap;
  const _Row({required this.depth, required this.icon, required this.iconColor, required this.label, required this.onTap, this.bold = false, this.leading});

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.only(left: 6.0 + widget.depth * 12, right: 8, top: 4, bottom: 4),
          decoration: BoxDecoration(color: _hover ? AppColors.surface : Colors.transparent, borderRadius: BorderRadius.circular(6)),
          child: Row(
            children: [
              SizedBox(width: 14, child: widget.leading ?? const SizedBox.shrink()),
              Icon(widget.icon, size: 14, color: widget.iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textDim, fontWeight: widget.bold ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}