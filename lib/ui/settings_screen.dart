// lib/ui/settings_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_config.dart';
import '../providers/chat_provider.dart';
import '../providers/config_provider.dart';
import '../theme/app_theme.dart';
import 'widgets/selectors.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _launchUrl() async {
    final url = Uri.parse('https://aistudio.google.com/app/apikey');
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configControllerProvider);
    final notifier = ref.read(configControllerProvider.notifier);
    final localTools = ref.watch(localToolsAvailableProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: AppColors.textDim),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        shape: const Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!localTools)
                const _Card(
                  child: Row(children: [
                    Icon(LucideIcons.globe, size: 16, color: AppColors.blue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Web preview: file & terminal permissions only take effect in the desktop app.', style: TextStyle(fontSize: 12.5, color: AppColors.textDim)),
                    ),
                  ]),
                ),
              _SectionTitle(icon: LucideIcons.shield_check, title: 'Permission mode', subtitle: 'How much Arzu can do before asking you.'),
              _Card(
                child: Column(
                  children: [
                    for (final m in PermissionMode.values)
                      _ModeRow(mode: m, selected: config.permissionMode == m, onTap: () => notifier.setMode(m)),
                  ],
                ),
              ),
              _SectionTitle(icon: LucideIcons.folder_lock, title: 'Allowed folders', subtitle: 'Arzu can only read & write inside these folders. Everything else is blocked.'),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (config.allowedFolders.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No folders added yet.', style: TextStyle(fontSize: 13, color: AppColors.textFaint))),
                    for (final folder in config.allowedFolders)
                      _FolderRow(path: folder, onRemove: () => notifier.removeFolder(folder)),
                    const SizedBox(height: 10),
                    _AddFolderButton(onPicked: notifier.addFolder),
                  ],
                ),
              ),
              _SectionTitle(icon: LucideIcons.key, title: 'Google Generative AI', subtitle: 'API Key for Gemini 3.5, 3.1 Pro etc.'),
              _Card(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: config.googleApiKey)..selection = TextSelection.fromPosition(TextPosition(offset: config.googleApiKey.length)),
                        obscureText: true,
                        style: const TextStyle(color: AppColors.text, fontSize: 13.5),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Enter Google AI Studio API Key',
                          hintStyle: TextStyle(color: AppColors.textFaint),
                          border: OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
                        ),
                        onChanged: (v) => notifier.setGoogleApiKey(v.trim()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      onPressed: _launchUrl,
                      icon: const Icon(LucideIcons.arrow_up_right, size: 16),
                      label: const Text('Get API Key'),
                    ),
                  ],
                ),
              ),
              _SectionTitle(icon: LucideIcons.cloud, title: 'Arzu Cloud (Gemma backend)', subtitle: 'Server-hosted model via the ilm_ai gateway. No local Ollama needed.'),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: TextEditingController(text: config.arzuCloudKey)..selection = TextSelection.fromPosition(TextPosition(offset: config.arzuCloudKey.length)),
                      obscureText: true,
                      style: const TextStyle(color: AppColors.text, fontSize: 13.5),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Arzu Cloud key (X-Arzu-Key)',
                        labelStyle: TextStyle(color: AppColors.textFaint),
                        hintText: 'Paste the ARZU_AI_KEY from the backend .env',
                        hintStyle: TextStyle(color: AppColors.textFaint),
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
                      ),
                      onChanged: (v) => notifier.setArzuCloudKey(v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: config.arzuCloudUrl)..selection = TextSelection.fromPosition(TextPosition(offset: config.arzuCloudUrl.length)),
                      style: const TextStyle(color: AppColors.text, fontSize: 13.5),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Gateway base URL',
                        labelStyle: TextStyle(color: AppColors.textFaint),
                        hintText: 'https://core.arzucoder.uz',
                        hintStyle: TextStyle(color: AppColors.textFaint),
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
                      ),
                      onChanged: (v) => notifier.setArzuCloudUrl(v),
                    ),
                    const SizedBox(height: 8),
                    const Text('Pick a "Arzu Cloud" model from the engine menu to use it.', style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
                  ],
                ),
              ),
              _SectionTitle(icon: LucideIcons.sparkles, title: 'Models', subtitle: 'Default model and the model used in test mode.'),
              _Card(
                child: Column(
                  children: [
                    _DropdownRow(
                      label: 'Default model (Complex logic)',
                      value: config.model,
                      items: [...kGoogleAiModels, ...kVertexModels, ...config.customModels],
                      onChanged: (v) => notifier.setModel(v),
                    ),
                    const Divider(height: 20, color: AppColors.borderSubtle),
                    _DropdownRow(
                      label: 'Fast model (Simple tasks)',
                      value: config.testModel,
                      items: [...kGoogleAiModels, ...kVertexModels, ...config.customModels],
                      onChanged: (v) => notifier.setTestModel(v),
                    ),
                    const Divider(height: 20, color: AppColors.borderSubtle),
                    _DropdownRow(
                      label: 'Image model (generate_image)',
                      value: config.imageModel,
                      items: kAvailableImageModels,
                      onChanged: (v) => notifier.setImageModel(v),
                    ),
                    const Divider(height: 20, color: AppColors.borderSubtle),
                    _SwitchRow(
                      label: 'Test mode',
                      subtitle: 'Use the cheaper/faster test model right now.',
                      value: config.testMode,
                      onChanged: notifier.setTestMode,
                    ),
                    const Divider(height: 20, color: AppColors.borderSubtle),
                    _TemperatureRow(value: config.temperature, onChanged: notifier.setTemperature),
                  ],
                ),
              ),
              _SectionTitle(icon: LucideIcons.box, title: 'Custom models', subtitle: 'Manually added custom models.'),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (config.customModels.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No custom models yet.', style: TextStyle(fontSize: 13, color: AppColors.textFaint))),
                    for (final m in config.customModels)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.box, size: 15, color: AppColors.accent),
                            const SizedBox(width: 10),
                            Expanded(child: Text('$m (${config.customModelEngines[m]})', style: AppTheme.mono(size: 12.5, color: AppColors.text), overflow: TextOverflow.ellipsis)),
                            IconButton(
                              icon: const Icon(LucideIcons.x, size: 15, color: AppColors.textFaint),
                              onPressed: () => notifier.removeCustomModel(m),
                              splashRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerLeft, child: _AddCustomModelButton()),
                  ],
                ),
              ),
              _SectionTitle(icon: LucideIcons.database, title: 'RAG embeddings (Vertex AI)', subtitle: 'Used strictly for indexing files. Provide JSON or use default credentials.'),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(config.serviceAccountPath.isEmpty ? LucideIcons.circle_alert : LucideIcons.circle_check, size: 15, color: config.serviceAccountPath.isEmpty ? AppColors.yellow : AppColors.green),
                        const SizedBox(width: 10),
                        Expanded(child: Text(config.serviceAccountPath.isEmpty ? 'Using ~/.arzu_code/service_account.json or gcloud ADC.' : config.serviceAccountPath, style: AppTheme.mono(size: 12, color: AppColors.textDim), overflow: TextOverflow.ellipsis)),
                        if (config.serviceAccountPath.isNotEmpty)
                          IconButton(icon: const Icon(LucideIcons.x, size: 15, color: AppColors.textFaint), onPressed: () => notifier.setServiceAccountPath(''), splashRadius: 16),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), foregroundColor: AppColors.text, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
                          final path = result?.files.single.path;
                          if (path != null) notifier.setServiceAccountPath(path);
                        },
                        icon: const Icon(LucideIcons.key_round, size: 16),
                        label: const Text('Choose service-account JSON'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionTitle({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
          ]),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textFaint)),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: child,
    );
  }
}

class _ModeRow extends StatelessWidget {
  final PermissionMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ModeRow({required this.mode, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Row(
          children: [
            Icon(selected ? LucideIcons.circle_check : LucideIcons.circle, size: 18, color: selected ? AppColors.accent : AppColors.textFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.text)),
                  Text(mode.description, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  const _FolderRow({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(LucideIcons.folder, size: 15, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(path, style: AppTheme.mono(size: 12.5, color: AppColors.text), overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(LucideIcons.x, size: 15, color: AppColors.textFaint), onPressed: onRemove, splashRadius: 16),
        ],
      ),
    );
  }
}

class _AddFolderButton extends StatelessWidget {
  final void Function(String) onPicked;
  const _AddFolderButton({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), foregroundColor: AppColors.text, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
        onPressed: () async {
          final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a folder Arzu can work in');
          if (dir != null) onPicked(dir);
        },
        icon: const Icon(LucideIcons.folder_plus, size: 16),
        label: const Text('Add folder'),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final void Function(String) onChanged;
  const _DropdownRow({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = items.contains(value) ? items : [value, ...items];
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.text))),
        const SizedBox(width: 12),
        Flexible(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: AppColors.surfaceHigh,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(10),
            style: const TextStyle(fontSize: 13, color: AppColors.text),
            items: [for (final m in options) DropdownMenuItem(value: m, child: Text(prettyModel(m), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => v == null ? null : onChanged(v),
          ),
        ),
      ],
    );
  }
}

class _AddCustomModelButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), foregroundColor: AppColors.text, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
      onPressed: () => showAddCustomModelDialog(context, ref),
      icon: const Icon(LucideIcons.plus, size: 16),
      label: const Text('Add custom model'),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;
  const _SwitchRow({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.text)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
            ],
          ),
        ),
        Switch(value: value, activeThumbColor: AppColors.accent, onChanged: onChanged),
      ],
    );
  }
}

class _TemperatureRow extends StatelessWidget {
  final double value;
  final void Function(double) onChanged;
  const _TemperatureRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Temperature', style: TextStyle(fontSize: 13.5, color: AppColors.text)),
        Expanded(
          child: Slider(value: value, min: 0, max: 1, divisions: 20, activeColor: AppColors.accent, label: value.toStringAsFixed(2), onChanged: onChanged),
        ),
        SizedBox(width: 36, child: Text(value.toStringAsFixed(2), textAlign: TextAlign.right, style: AppTheme.mono(size: 12.5, color: AppColors.textDim))),
      ],
    );
  }
}