// lib/ui/widgets/message_bubble.dart
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../models/chat_message.dart';
import '../../models/tool_call.dart';
import '../../theme/app_theme.dart';
import 'tool_call_card.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _UserBubble(message: message);
    return _AssistantBubble(message: message);
  }
}

class _UserBubble extends StatelessWidget {
  final ChatMessage message;
  const _UserBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
            color: AppColors.surfaceHigh,
            child: const Icon(LucideIcons.user, size: 15, color: AppColors.text),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final path in message.attachments) _AttachmentThumb(path: path),
                      ],
                    ),
                  ),
                if (message.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _ClickableText(text: message.text),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  final String path;
  const _AttachmentThumb({required this.path});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: file.existsSync() ? Image.file(file, fit: BoxFit.cover) : const Icon(LucideIcons.image_off, size: 22, color: AppColors.textFaint),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final ChatMessage message;
  const _AssistantBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
            color: AppColors.accent,
            child: const Icon(LucideIcons.asterisk, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.text.trim().isNotEmpty) _md(context, message.text),
                if (message.toolCalls.isNotEmpty) _ToolCallsGroup(calls: message.toolCalls, running: message.streaming),
                if (message.thinking != null) _Thinking(text: message.thinking!),
                if (message.error != null) _ErrorBox(text: message.error!),
                if (message.text.trim().isEmpty && message.toolCalls.isEmpty && message.thinking == null && message.error == null && message.streaming)
                  const _Thinking(text: 'Thinking…'),
                const SizedBox(height: 8),
                _DurationTimer(start: message.startedAt, end: message.completedAt, running: message.streaming),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _md(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MarkdownBody(
        data: text,
        selectable: true,
        onTapLink: (text, href, title) {
          if(href != null) {
            launchUrl(Uri.parse(href));
          }
        },
        builders: {'code': _CodeBlockBuilder()},
        imageBuilder: (uri, title, alt) => _MarkdownImage(uri: uri, alt: alt),
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(fontSize: 14.5, color: AppColors.text, height: 1.55),
          h1: const TextStyle(fontSize: 20, color: AppColors.text, fontWeight: FontWeight.w700),
          h2: const TextStyle(fontSize: 17, color: AppColors.text, fontWeight: FontWeight.w700),
          h3: const TextStyle(fontSize: 15, color: AppColors.text, fontWeight: FontWeight.w600),
          listBullet: const TextStyle(fontSize: 14.5, color: AppColors.text, height: 1.5),
          code: GoogleFonts.jetBrainsMono(fontSize: 12.5, color: AppColors.accentHover, backgroundColor: AppColors.surface),
          codeblockDecoration: BoxDecoration(color: const Color(0xFF161513), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          codeblockPadding: const EdgeInsets.all(0),
          blockquoteDecoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6), border: const Border(left: BorderSide(color: AppColors.accent, width: 3))),
          a: const TextStyle(color: AppColors.blue, decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}

class _ToolCallsGroup extends StatefulWidget {
  final List<ToolCall> calls;
  final bool running;
  const _ToolCallsGroup({required this.calls, required this.running});

  @override
  State<_ToolCallsGroup> createState() => _ToolCallsGroupState();
}

class _ToolCallsGroupState extends State<_ToolCallsGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.calls.any((c) => c.status == ToolStatus.error);

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    widget.running ? LucideIcons.loader : (hasError ? LucideIcons.triangle_alert : LucideIcons.circle_check),
                    size: 15,
                    color: widget.running ? AppColors.blue : (hasError ? AppColors.red : AppColors.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.calls.length} operations ${widget.running ? 'running...' : 'completed'}',
                      style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(_expanded ? LucideIcons.chevron_up : LucideIcons.chevron_down, size: 16, color: AppColors.textDim),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderSubtle))),
              child: Column(children: widget.calls.map((c) => ToolCallCard(call: c)).toList()),
            ),
        ],
      ),
    );
  }
}

class _DurationTimer extends StatefulWidget {
  final DateTime start;
  final DateTime? end;
  final bool running;

  const _DurationTimer({required this.start, this.end, required this.running});

  @override
  State<_DurationTimer> createState() => _DurationTimerState();
}

class _DurationTimerState extends State<_DurationTimer> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.running && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.end ?? DateTime.now();
    final diff = end.difference(widget.start);
    final sec = (diff.inMilliseconds / 1000).toStringAsFixed(1);
    return Row(
      children: [
        Icon(LucideIcons.clock, size: 12, color: AppColors.textFaint),
        const SizedBox(width: 4),
        Text('${sec}s', style: AppTheme.mono(size: 11, color: AppColors.textFaint)),
      ],
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final textContent = element.textContent;
    if (!textContent.contains('\n')) return null;
    return _CodeBlock(code: textContent);
  }
}

class _CodeBlock extends StatefulWidget {
  final String code;
  const _CodeBlock({required this.code});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161513),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Code', style: AppTheme.mono(size: 11, color: AppColors.textFaint)),
                Row(
                  children: [
                    _ActionButton(
                      icon: _copied ? LucideIcons.check : LucideIcons.copy,
                      label: _copied ? 'Copied!' : 'Copy',
                      color: _copied ? AppColors.green : AppColors.textFaint,
                      onTap: _copy,
                    ),
                    const SizedBox(width: 14),
                    _ActionButton(
                      icon: LucideIcons.download,
                      label: 'Save',
                      onTap: () async {
                        final path = await FilePicker.platform.saveFile(dialogTitle: 'Save code', fileName: 'code_snippet.txt');
                        if (path != null) await File(path).writeAsString(widget.code);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: _ClickableText(text: widget.code.trimRight(), isCode: true),
          ),
        ],
      ),
    );
  }
}

class _MarkdownImage extends StatelessWidget {
  final Uri uri;
  final String? alt;
  const _MarkdownImage({required this.uri, this.alt});

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      image = Image.network(uri.toString(), fit: BoxFit.contain, errorBuilder: _err);
    } else {
      final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
      image = Image.file(File(path), fit: BoxFit.contain, errorBuilder: _err);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: image),
      ),
    );
  }

  Widget _err(BuildContext context, Object error, StackTrace? stack) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.image_off, size: 16, color: AppColors.textFaint),
          const SizedBox(width: 8),
          Flexible(child: Text(alt ?? 'Image unavailable', style: const TextStyle(fontSize: 12, color: AppColors.textFaint))),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap, this.color = AppColors.textFaint});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Avatar({required this.color, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Center(child: child),
    );
  }
}

class _Thinking extends StatefulWidget {
  final String text;
  const _Thinking({required this.text});
  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
            child: const Icon(LucideIcons.loader, size: 13, color: AppColors.accent),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(widget.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.mono(size: 12, color: AppColors.textDim)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String text;
  const _ErrorBox({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.triangle_alert, size: 15, color: AppColors.red),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(text, style: const TextStyle(fontSize: 12.5, color: AppColors.red, height: 1.4))),
        ],
      ),
    );
  }
}

class _ClickableText extends StatelessWidget {
  final String text;
  final bool isCode;
  const _ClickableText({required this.text, this.isCode = false});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final urlRegex = RegExp(r'https?://[^\s/$.?#].[^\s]*|(/[\w\s.-]+)+/?');

    int lastMatchEnd = 0;

    for (final match in urlRegex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }

      final matchedText = match.group(0)!;
      final isHttp = matchedText.startsWith('http');
      final uri = isHttp ? Uri.tryParse(matchedText) : Uri.file(matchedText);

      if (uri != null) {
        spans.add(
          TextSpan(
            text: matchedText,
            style: const TextStyle(color: AppColors.blue, decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()..onTap = () {
              launchUrl(uri);
            },
          ),
        );
      } else {
        spans.add(TextSpan(text: matchedText));
      }
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    final baseStyle = isCode
        ? GoogleFonts.jetBrainsMono(fontSize: 12.5, color: AppColors.textDim, height: 1.5)
        : const TextStyle(fontSize: 14.5, color: AppColors.text, height: 1.5);

    return SelectableText.rich(
      TextSpan(
        style: baseStyle,
        children: spans,
      ),
    );
  }
}