import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../providers/chat_provider.dart';
import '../../theme/app_theme.dart';

const _imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

class Composer extends ConsumerStatefulWidget {
  const Composer({super.key});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;
  bool _dragging = false;
  final List<String> _attachments = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _addPaths(Iterable<String> paths) {
    final images = paths.where((path) => _imageExtensions.contains(p.extension(path).toLowerCase()));
    if (images.isEmpty) return;
    setState(() {
      for (final path in images) {
        if (!_attachments.contains(path)) _attachments.add(path);
      }
    });
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      dialogTitle: 'Attach image(s)',
    );
    if (result != null) {
      _addPaths(result.files.map((f) => f.path).whereType<String>());
    }
  }

  Future<void> _pasteImage() async {
    final imageBytes = await Pasteboard.image;
    if (imageBytes != null) {
      final tempDir = await getTemporaryDirectory();
      final path = p.join(tempDir.path, '${DateTime.now().millisecondsSinceEpoch}.png');
      final file = File(path);
      await file.writeAsBytes(imageBytes);
      setState(() {
        if (!_attachments.contains(path)) _attachments.add(path);
      });
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final attachments = List<String>.from(_attachments);
    _controller.clear();
    setState(() {
      _hasText = false;
      _attachments.clear();
    });
    ref.read(chatControllerProvider.notifier).send(text, attachments: attachments);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(chatControllerProvider).isRunning;
    final canSend = _hasText || _attachments.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) {
          setState(() => _dragging = false);
          _addPaths(detail.files.map((f) => f.path));
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _dragging ? AppColors.accent : AppColors.border,
              width: _dragging ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final path in _attachments)
                          _AttachChip(
                            path: path,
                            onRemove: () => setState(() => _attachments.remove(path)),
                          ),
                      ],
                    ),
                  ),
                ),
              RawKeyboardListener(
                focusNode: FocusNode(),
                onKey: (event) {
                  if (event.isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyV) {
                    _pasteImage();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                        if (!running) _send();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 8,
                      style: const TextStyle(fontSize: 14.5, color: AppColors.text, height: 1.5),
                      cursorColor: AppColors.accent,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: _dragging ? 'Drop images here…' : 'Ask Arzu to build... (Cmd+V to paste image)',
                        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 14.5),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 10, 8),
                child: Row(
                  children: [
                    _IconAction(icon: LucideIcons.image_plus, tooltip: 'Attach image from files', onTap: _pickImages),
                    _IconAction(icon: LucideIcons.clipboard, tooltip: 'Paste image from clipboard', onTap: _pasteImage),
                    const SizedBox(width: 6),
                    const Icon(LucideIcons.corner_down_left, size: 12, color: AppColors.textFaint),
                    const SizedBox(width: 5),
                    const Text('to send · Shift+Enter for newline', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
                    const Spacer(),
                    if (running)
                      _SendButton(icon: LucideIcons.square, color: AppColors.red, onTap: ref.read(chatControllerProvider.notifier).stop)
                    else
                      _SendButton(
                        icon: LucideIcons.arrow_up,
                        color: canSend ? AppColors.accent : AppColors.surfaceHigh,
                        iconColor: canSend ? Colors.white : AppColors.textFaint,
                        onTap: canSend ? _send : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachChip extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  const _AttachChip({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: file.existsSync()
                ? Image.file(file, fit: BoxFit.cover)
                : const Icon(LucideIcons.image, size: 18, color: AppColors.textFaint),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(LucideIcons.x, size: 12, color: AppColors.text),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconAction({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: AppColors.textDim),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;
  const _SendButton({required this.icon, required this.color, this.iconColor = Colors.white, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}