import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_provider.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import 'composer.dart';
import 'message_bubble.dart';
import 'permission_banner.dart';

class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key});

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _scroll = ScrollController();
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 50) {
        _userScrolledUp = true;
      } else {
        _userScrolledUp = false;
      }
    });
  }

  void _scrollToBottom() {
    if (_userScrolledUp) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final messages = chat.messages;

    ref.listen(chatControllerProvider, (prev, next) => _scrollToBottom());

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? const _Welcome()
                  : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                itemCount: messages.length,
                itemBuilder: (_, i) => MessageBubble(message: messages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  if (chat.pendingApproval != null) PermissionBanner(pending: chat.pendingApproval!),
                  const Composer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome();

  static const _prompts = [
    ('Codebase Qidiruv (RAG)', LucideIcons.brain_circuit, 'Use semantic_search to deeply understand my project architecture. Explain how the state management is structured.'),
    ('Create a new Flutter app', LucideIcons.smartphone, 'Create a brand-new Flutter app called hello_arzu in my allowed folder, run it, and show me it builds.'),
    ('Fix failing tests', LucideIcons.bug, 'Run the test suite in my project, find what is failing, and fix it automatically.'),
    ('Set up a Git repo', LucideIcons.git_branch, 'Initialize a git repository in my project, add a sensible .gitignore, and make the first commit.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localTools = ref.watch(localToolsAvailableProvider);
    final folders = ref.watch(configControllerProvider).allowedFolders;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(16)),
              child: const Icon(LucideIcons.asterisk, size: 34, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text('What should we build today?', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 8),
            const Text(
              'Arzu Code is an agentic engineer — it reads, writes, and runs code for you.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textDim),
            ),
            const SizedBox(height: 24),
            if (!localTools)
              const _Notice(icon: LucideIcons.globe, color: AppColors.blue, text: 'You are using the web preview. File and terminal tools are only available in the desktop app.')
            else if (folders.isEmpty)
              const _Notice(icon: LucideIcons.folder_lock, color: AppColors.yellow, text: 'No allowed folders yet. Open Settings → Permissions and add a workspace folder so Arzu can read and write files.'),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final (label, icon, prompt) in _prompts)
                    _PromptChip(label: label, icon: icon, onTap: () => ref.read(chatControllerProvider.notifier).send(prompt)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color, height: 1.4))),
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PromptChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.accent),
              const SizedBox(width: 9),
              Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}