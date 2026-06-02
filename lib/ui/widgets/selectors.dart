import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_config.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';

String prettyModel(String id) {
  return switch (id) {
    'gemini-3.1-pro-preview' => 'Gemini 3.1 Pro (Google)',
    'gemini-3.5-flash' => 'Gemini 3.5 Flash (Google)',
    'gemini-3.1-flash-lite' => 'Gemini 3.1 Flash Lite (Google)',
    'gemini-2.5-pro' => 'Gemini 2.5 Pro (Vertex)',
    'gemini-2.5-flash' => 'Gemini 2.5 Flash (Vertex)',
    'qwen2.5-coder:3b' => 'Qwen 2.5 Coder',
    'gemma2:2b' => 'Gemma 2',
    'llama3.1:8b' => 'Llama 3.1',
    'deepseek-coder-v2' => 'DeepSeek V2',
    _ => id,
  };
}

Future<void> showAddCustomModelDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  String selectedEngine = 'google';

  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surfaceHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Add custom model', style: TextStyle(color: AppColors.text, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: AppColors.text, fontSize: 13.5),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: 'Model ID (e.g. gemini-experimental)',
                  hintStyle: const TextStyle(color: AppColors.textFaint),
                  filled: true,
                  fillColor: AppColors.surface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Select Engine:', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Radio<String>(
                    value: 'google',
                    groupValue: selectedEngine,
                    activeColor: AppColors.accent,
                    onChanged: (v) => setState(() => selectedEngine = v!),
                  ),
                  const Text('Google AI (API Key)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                ],
              ),
              Row(
                children: [
                  Radio<String>(
                    value: 'vertex',
                    groupValue: selectedEngine,
                    activeColor: AppColors.accent,
                    onChanged: (v) => setState(() => selectedEngine = v!),
                  ),
                  const Text('Vertex AI (Firebase)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textDim)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop({'id': controller.text.trim(), 'engine': selectedEngine}),
              child: const Text('Add', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
    },
  );

  if (result != null && result['id']!.isNotEmpty) {
    ref.read(configControllerProvider.notifier).addCustomModel(result['id']!, result['engine']!);
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.text, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(LucideIcons.chevrons_up_down, size: 12, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

class ModelSelector extends ConsumerWidget {
  const ModelSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configControllerProvider);
    final notifier = ref.read(configControllerProvider.notifier);
    final active = config.activeModel;

    return PopupMenuButton<String>(
      tooltip: 'Choose AI Engine & Model',
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (v) {
        if (v == '__test') {
          notifier.setTestMode(true);
        } else if (v == '__add_custom') {
          showAddCustomModelDialog(context, ref);
        } else if (kGoogleAiModels.contains(v) || kVertexModels.contains(v) || config.customModels.contains(v)) {
          notifier.setModel(v);
          notifier.setTestMode(false);
          notifier.setUseLocalModel(false);
        } else if (kAvailableLocalModels.contains(v)) {
          notifier.setLocalModel(v);
          notifier.setUseLocalModel(true);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          enabled: false,
          child: Text('☁️ GOOGLE GENERATIVE AI (API Key)', style: TextStyle(fontSize: 11, color: AppColors.textFaint, fontWeight: FontWeight.bold)),
        ),
        for (final m in kGoogleAiModels)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                Icon(
                  (!config.useLocalModel && !config.testMode && config.model == m) ? LucideIcons.check : LucideIcons.sparkles,
                  size: 15,
                  color: (!config.useLocalModel && !config.testMode && config.model == m) ? AppColors.accent : AppColors.textFaint,
                ),
                const SizedBox(width: 8),
                Text(prettyModel(m), style: const TextStyle(color: AppColors.text, fontSize: 13)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          enabled: false,
          child: Text('☁️ VERTEX AI (Firebase)', style: TextStyle(fontSize: 11, color: AppColors.textFaint, fontWeight: FontWeight.bold)),
        ),
        for (final m in kVertexModels)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                Icon(
                  (!config.useLocalModel && !config.testMode && config.model == m) ? LucideIcons.check : LucideIcons.cloud,
                  size: 15,
                  color: (!config.useLocalModel && !config.testMode && config.model == m) ? AppColors.accent : AppColors.textFaint,
                ),
                const SizedBox(width: 8),
                Text(prettyModel(m), style: const TextStyle(color: AppColors.text, fontSize: 13)),
              ],
            ),
          ),
        if (config.customModels.isNotEmpty) const PopupMenuDivider(),
        for (final m in config.customModels)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                Icon(
                  (!config.useLocalModel && !config.testMode && config.model == m) ? LucideIcons.check : LucideIcons.box,
                  size: 15,
                  color: (!config.useLocalModel && !config.testMode && config.model == m) ? AppColors.accent : AppColors.textFaint,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('${prettyModel(m)} (${config.customModelEngines[m] ?? 'Unknown'})', style: const TextStyle(color: AppColors.text, fontSize: 13), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        const PopupMenuItem(
          value: '__add_custom',
          child: Row(
            children: [
              Icon(LucideIcons.plus, size: 15, color: AppColors.accent),
              SizedBox(width: 8),
              Text('Add custom model…', style: TextStyle(color: AppColors.accent, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '__test',
          child: Row(
            children: [
              Icon(
                config.testMode && !config.useLocalModel ? LucideIcons.check : LucideIcons.zap,
                size: 15,
                color: config.testMode && !config.useLocalModel ? AppColors.green : AppColors.textFaint,
              ),
              const SizedBox(width: 8),
              Text('Fast Cloud Mode (${prettyModel(config.testModel)})', style: const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          enabled: false,
          child: Text('💻 LOCAL MODELS (Ollama)', style: TextStyle(fontSize: 11, color: AppColors.textFaint, fontWeight: FontWeight.bold)),
        ),
        for (final m in kAvailableLocalModels)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                Icon(
                  (config.useLocalModel && config.localModel == m) ? LucideIcons.check : LucideIcons.cpu,
                  size: 15,
                  color: (config.useLocalModel && config.localModel == m) ? AppColors.purple : AppColors.textFaint,
                ),
                const SizedBox(width: 8),
                Text(prettyModel(m), style: const TextStyle(color: AppColors.text, fontSize: 13)),
              ],
            ),
          ),
      ],
      child: _Chip(
        icon: config.useLocalModel ? LucideIcons.cpu : (config.testMode ? LucideIcons.zap : LucideIcons.sparkles),
        label: prettyModel(active),
        color: config.useLocalModel ? AppColors.purple : (config.testMode ? AppColors.yellow : AppColors.accent),
      ),
    );
  }
}

class ModeSelector extends ConsumerWidget {
  const ModeSelector({super.key});

  IconData _icon(PermissionMode m) => switch (m) {
    PermissionMode.ask => LucideIcons.shield_check,
    PermissionMode.acceptEdits => LucideIcons.file_check,
    PermissionMode.auto => LucideIcons.zap,
  };

  Color _color(PermissionMode m) => switch (m) {
    PermissionMode.ask => AppColors.blue,
    PermissionMode.acceptEdits => AppColors.green,
    PermissionMode.auto => AppColors.yellow,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configControllerProvider);
    final notifier = ref.read(configControllerProvider.notifier);

    return PopupMenuButton<PermissionMode>(
      tooltip: 'Permission mode',
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: notifier.setMode,
      itemBuilder: (_) => [
        for (final m in PermissionMode.values)
          PopupMenuItem(
            value: m,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icon(m), size: 15, color: _color(m)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.label, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(m.description, style: const TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: _Chip(
        icon: _icon(config.permissionMode),
        label: config.permissionMode.short,
        color: _color(config.permissionMode),
      ),
    );
  }
}