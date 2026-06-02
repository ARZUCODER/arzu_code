import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/chat_message.dart';

class ExportService {
  static Future<void> exportSessionAsMarkdown(ChatSession session) async {
    final buffer = StringBuffer();
    buffer.writeln('# ${session.title}');
    buffer.writeln('Date: ${session.createdAt.toLocal().toString().split('.')[0]}\n');
    buffer.writeln('---\n');

    for (final msg in session.messages) {
      final role = msg.isUser ? '👤 You' : '🤖 Arzu Code';
      buffer.writeln('### $role');

      if (msg.text.trim().isNotEmpty) {
        buffer.writeln(msg.text.trim());
        buffer.writeln();
      }

      if (msg.toolCalls.isNotEmpty) {
        buffer.writeln('**Tools Used:**');
        for (final tc in msg.toolCalls) {
          buffer.writeln('- `${tc.summary}` (${tc.status.name})');
          if (tc.result != null && tc.result!.output != null) {
            final out = tc.result!.output!.trim();
            if (out.isNotEmpty) {
              buffer.writeln('  ```text');
              buffer.writeln('  ${out.replaceAll('\n', '\n  ')}');
              buffer.writeln('  ```');
            }
          }
        }
        buffer.writeln();
      }
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Chat History',
      fileName: '${session.title.replaceAll(' ', '_').toLowerCase()}.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
    );

    if (path != null) {
      await File(path).writeAsString(buffer.toString());
    }
  }
}