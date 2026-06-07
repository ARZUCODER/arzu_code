import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/chat_message.dart';

class ExportService {
  /// Auto-saves the session as Markdown into ~/Desktop/arzu test md/ (created if
  /// missing). The filename is a short slug of the title + the model name, e.g.
  /// `habit_tracker_qwen.md`. Returns the saved path (or null on failure).
  static Future<String?> exportSessionAsMarkdown(ChatSession session) async {
    final buffer = StringBuffer();
    buffer.writeln('# ${session.title}');
    buffer.writeln('Date: ${session.createdAt.toLocal().toString().split('.')[0]}');

    final models = <String>{
      for (final m in session.messages)
        if (!m.isUser && (m.model ?? '').isNotEmpty) m.model!,
    };
    if (models.isNotEmpty) {
      buffer.writeln('Model(s): ${models.join(', ')}');
    }
    buffer.writeln('Total tokens: ${session.totalTokens} '
        '(input ${session.totalInputTokens} · output ${session.totalOutputTokens}'
        '${session.totalThoughtTokens > 0 ? ' · thinking ${session.totalThoughtTokens}' : ''})');
    buffer.writeln();
    buffer.writeln('---\n');

    for (final msg in session.messages) {
      final role = msg.isUser ? '👤 You' : '🤖 Arzu Code';
      buffer.writeln('### $role');

      if (!msg.isUser && ((msg.model ?? '').isNotEmpty || msg.totalTokens > 0)) {
        final parts = <String>[];
        if ((msg.model ?? '').isNotEmpty) parts.add('Model: `${msg.model}`');
        if (msg.totalTokens > 0) {
          parts.add('Tokens: ${msg.totalTokens} (in ${msg.inputTokens} · out ${msg.outputTokens}'
              '${msg.thoughtTokens > 0 ? ' · think ${msg.thoughtTokens}' : ''})');
        }
        buffer.writeln('_${parts.join(' · ')}_');
        buffer.writeln();
      }

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

    try {
      final home = Platform.environment['HOME'] ?? '';
      final dir = Directory(p.join(home, 'Desktop', 'arzu test md'));
      await dir.create(recursive: true);

      final fileName = '${_slug(session.title)}_${_modelTag(session.lastModel)}';
      var path = p.join(dir.path, '$fileName.md');
      var n = 1;
      while (File(path).existsSync()) {
        path = p.join(dir.path, '${fileName}_$n.md');
        n++;
      }
      await File(path).writeAsString(buffer.toString());
      return path;
    } catch (_) {
      return null;
    }
  }

  static String _slug(String title) {
    var s = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_|_$'), '');
    if (s.isEmpty) s = 'chat';
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  static String _modelTag(String? model) {
    final m = (model ?? '').toLowerCase();
    if (m.contains('qwen')) return 'qwen';
    if (m.contains('gemma')) return 'gemma';
    if (m.contains('gemini')) return 'gemini';
    if (m.isEmpty) return 'ai';
    return m.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
