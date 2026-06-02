// lib/ui/widgets/folder_to_txt_dialog.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';

Future<void> showFolderToTxtDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => const Dialog(
      backgroundColor: Colors.transparent,
      child: _FolderToTxtWidget(),
    ),
  );
}

class _FolderToTxtWidget extends StatefulWidget {
  const _FolderToTxtWidget();

  @override
  State<_FolderToTxtWidget> createState() => _FolderToTxtWidgetState();
}

class _FolderToTxtWidgetState extends State<_FolderToTxtWidget> {
  bool _isDragging = false;
  bool _isProcessing = false;
  String _statusText = 'Papkani shu yerga tashlang\nyoki tanlash uchun bosing';
  String? _lastOutput;

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Papkani tanlang');
    if (dir != null) {
      await _processDirectory(dir);
    }
  }

  Future<void> _processDirectory(String dirPath) async {
    setState(() {
      _isProcessing = true;
      _statusText = 'Fayllar o\'qilmoqda...';
      _lastOutput = null;
    });

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) throw Exception();

      final entities = dir.listSync(recursive: true);
      final List<File> files = [];
      for (var entity in entities) {
        if (entity is File && !entity.path.contains('/.git/') && !entity.path.contains('/node_modules/')) {
          files.add(entity);
        }
      }

      if (files.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusText = 'Papka bo\'sh yoki yaroqli fayllar yo\'q\nBoshqa papka tanlash uchun bosing';
        });
        return;
      }

      final home = Platform.environment['HOME'] ?? '';
      final desktop = p.join(home, 'Desktop', 'Arzu_Code_Exports');
      await Directory(desktop).create(recursive: true);

      final outPath = p.join(desktop, 'folder_to_txt_${DateTime.now().millisecondsSinceEpoch}.txt');
      final fileOut = File(outPath);
      final sink = fileOut.openWrite();

      for (var file in files) {
        final relPath = p.relative(file.path, from: p.dirname(dirPath));
        sink.writeln('==================================================');
        sink.writeln('PATH: $relPath');
        sink.writeln('==================================================');
        try {
          String content = await file.readAsString();
          sink.writeln(content);
        } catch (e) {
          sink.writeln('[Binar fayl yoki o\'qib bo\'lmaydigan format]');
        }
        sink.writeln('\n\n');
      }

      await sink.close();

      setState(() {
        _isProcessing = false;
        _statusText = 'Saqlandi! Jami: ${files.length} ta fayl.\nYana papka tanlash uchun bosing';
        _lastOutput = outPath;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = 'Xatolik yuz berdi\nQayta urinish uchun bosing';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 460,
      height: 380,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('FOLDER TO TXT', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, size: 20, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: DropTarget(
                onDragDone: (details) async {
                  if (details.files.isNotEmpty) {
                    final path = details.files.first.path;
                    if (await FileSystemEntity.isDirectory(path)) {
                      await _processDirectory(path);
                    } else {
                      setState(() {
                        _statusText = 'Fayl emas, papka tashlang!\nYoki papka tanlash uchun bosing';
                      });
                    }
                  }
                },
                onDragEntered: (_) => setState(() => _isDragging = true),
                onDragExited: (_) => setState(() => _isDragging = false),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isProcessing ? null : _pickFolder,
                    borderRadius: BorderRadius.circular(12),
                    hoverColor: AppColors.surfaceHigh.withOpacity(0.5),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isDragging ? AppColors.accent.withOpacity(0.1) : AppColors.surface,
                        border: Border.all(
                          color: _isDragging ? AppColors.accent : AppColors.border,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.snippet_folder_rounded,
                            size: 60,
                            color: _isDragging ? AppColors.accent : AppColors.textDim,
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              _statusText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _isProcessing ? AppColors.yellow : AppColors.text,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                          if (_lastOutput != null && !_isProcessing) ...[
                            const SizedBox(height: 16),
                            InkWell(
                              onTap: () => launchUrl(Uri.file(_lastOutput!)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'Saqlandi:\n$_lastOutput',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11, color: AppColors.green, decoration: TextDecoration.underline),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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