import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tool_call.dart';
import '../../providers/chat_provider.dart';
import '../../theme/app_theme.dart';

class PermissionBanner extends ConsumerWidget {
  final PendingApproval pending;
  const PermissionBanner({super.key, required this.pending});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(chatControllerProvider.notifier);
    final tc = pending.toolCall;
    final isCommand = tc.name == 'run_command';
    final isGrant = tc.name == '__grant_folder';
    final folder = tc.args['folder'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isGrant ? LucideIcons.folder_lock : LucideIcons.shield_alert, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                isGrant ? 'Bu papkaga ruxsat berilsinmi?' : (isCommand ? 'Run this command?' : 'Allow this action?'),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
            ],
          ),
          if (isGrant) ...[
            const SizedBox(height: 4),
            const Text('Arzu shu papkada ishlamoqchi (allowed folders\'ga qo\'shiladi):', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF161513), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: SelectableText(isGrant ? folder : tc.summary, style: AppTheme.mono(size: 12.5, color: AppColors.text, height: 1.4)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: isGrant
                ? [
                    _btn(label: 'Ruxsat berish', icon: LucideIcons.check, filled: true, onTap: () => controller.resolveApproval(true)),
                    _btn(label: 'Yo\'q', icon: LucideIcons.x, danger: true, onTap: () => controller.resolveApproval(false)),
                  ]
                : [
                    _btn(label: 'Allow', icon: LucideIcons.check, filled: true, onTap: () => controller.resolveApproval(true)),
                    _btn(label: 'Always allow ${_ruleLabel(tc)}', icon: LucideIcons.check_check, onTap: () => controller.resolveApproval(true, always: true)),
                    _btn(label: 'Deny', icon: LucideIcons.x, danger: true, onTap: () => controller.resolveApproval(false)),
                  ],
          ),
        ],
      ),
    );
  }

  String _ruleLabel(ToolCall tc) {
    if (tc.name == 'run_command') {
      final sig = tc.ruleSignature.split(':');
      return sig.length > 1 ? '`${sig[1]}`' : 'commands';
    }
    return tc.name.replaceAll('_', ' ');
  }

  Widget _btn({required String label, required IconData icon, required VoidCallback onTap, bool filled = false, bool danger = false}) {
    final bg = filled ? AppColors.accent : (danger ? Colors.transparent : AppColors.surface);
    final fg = filled ? Colors.white : (danger ? AppColors.red : AppColors.text);
    final borderColor = danger ? AppColors.red.withValues(alpha: 0.5) : AppColors.border;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: filled ? null : Border.all(color: borderColor)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}