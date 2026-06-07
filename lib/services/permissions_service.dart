import 'package:path/path.dart' as p;

import '../models/app_config.dart';

class PermissionsService {
  AppConfig config;

  PermissionsService(this.config);

  bool isPathAllowed(String targetPath) {
    if (config.allowedFolders.isEmpty) return false;
    final target = p.normalize(p.absolute(targetPath));
    for (final root in config.allowedFolders) {
      final r = p.normalize(p.absolute(root));
      if (target == r || p.isWithin(r, target)) return true;
    }
    return false;
  }

  String? pathDenialReason(String targetPath) {
    if (isPathAllowed(targetPath)) return null;
    if (config.allowedFolders.isEmpty) {
      return 'No workspace folders are allowed yet. Add one in Permissions.';
    }
    return '"$targetPath" is outside the allowed folders. '
        'Add its folder in Permissions first.';
  }

  // Always blocked regardless of user config — whole-disk scans are slow, dump
  // huge output, and trigger macOS Music/iCloud privacy prompts.
  static const _alwaysBlocked = ['find / ', 'find ~ ', 'find / -', 'mdfind '];

  String? blockedCommandPattern(String command) {
    final lower = command.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final pat in [..._alwaysBlocked, ...config.blockedCommandPatterns]) {
      if (lower.contains(pat.toLowerCase())) return pat;
    }
    return null;
  }

  bool requiresApproval(String toolName, String ruleSignature) {
    if (config.alwaysAllow[ruleSignature] == true) return false;

    switch (config.permissionMode) {
      case PermissionMode.auto:
        return false;
      case PermissionMode.acceptEdits:
        return toolName == 'run_command' ||
            toolName == 'start_background_process' ||
            toolName == 'stop_process';
      case PermissionMode.ask:
        return _mutating.contains(toolName);
    }
  }

  static const _mutating = {
    'write_file',
    'edit_file',
    'make_dir',
    'run_command',
    'create_project',
    'download_asset',
    'generate_image',
    'start_background_process',
    'stop_process',
  };
}