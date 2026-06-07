import 'dart:io';

/// Detects where the user's dev toolchain lives so the agent never has to ask
/// "where is flutter installed?". Results are injected into the system prompt.
///
/// Many GUI apps on macOS launch with a minimal PATH that misses Homebrew,
/// asdf, fvm, nvm, etc. We probe a real login shell (`zsh -lc`) which sources
/// the user's profile, so `which` reflects what they actually have.
class EnvironmentService {
  EnvironmentService._();

  /// Populated by [detect]. Read by the agent when building the system prompt.
  static String? promptBlock;
  static Map<String, String> tools = const {};
  static bool detected = false;

  static const _probe = <String>[
    'flutter',
    'dart',
    'node',
    'npm',
    'npx',
    'python3',
    'pip3',
    'git',
    'go',
    'cargo',
    'java',
    'docker',
    'rg',
  ];

  static Future<void> detect() async {
    if (detected) return;
    final found = <String, String>{};

    for (final tool in _probe) {
      try {
        final res = await Process.run('/bin/zsh', ['-lc', 'command -v $tool'])
            .timeout(const Duration(seconds: 6));
        final path = (res.stdout as String).trim().split('\n').first.trim();
        if (res.exitCode == 0 && path.isNotEmpty) {
          found[tool] = path;
        }
      } catch (_) {
        // tool not installed or shell timed out — skip silently
      }
    }

    // Flutter/Dart are often installed OUTSIDE PATH (e.g. ~/Documents/flutter/bin).
    // Probe known locations so the agent never resorts to `find /` (slow, dumps
    // thousands of lines, and triggers macOS Music/iCloud privacy prompts).
    final h = Platform.environment['HOME'] ?? '';
    final fallbacks = <String, List<String>>{
      'flutter': [
        '$h/Documents/flutter/bin/flutter',
        '$h/flutter/bin/flutter',
        '$h/development/flutter/bin/flutter',
        '$h/fvm/default/bin/flutter',
        '/opt/homebrew/bin/flutter',
        '/usr/local/bin/flutter',
      ],
      'dart': [
        '$h/Documents/flutter/bin/dart',
        '$h/flutter/bin/dart',
        '/opt/homebrew/bin/dart',
        '/usr/local/bin/dart',
      ],
    };
    fallbacks.forEach((tool, paths) {
      if (found.containsKey(tool)) return;
      for (final pth in paths) {
        if (File(pth).existsSync()) {
          found[tool] = pth;
          break;
        }
      }
    });

    String? osVersion;
    try {
      final res = await Process.run('sw_vers', ['-productVersion'])
          .timeout(const Duration(seconds: 4));
      if (res.exitCode == 0) osVersion = (res.stdout as String).trim();
    } catch (_) {}

    tools = found;
    detected = true;

    final home = Platform.environment['HOME'] ?? '~';
    final b = StringBuffer();
    b.writeln('\n\n# HOST ENVIRONMENT (auto-detected — use these exact paths)');
    b.writeln('- OS: macOS ${osVersion ?? ''} (${Platform.operatingSystemVersion})');
    b.writeln('- HOME: $home');
    b.writeln('- Shell: /bin/zsh (commands run via `zsh -lc`, login profile sourced)');
    if (found.isEmpty) {
      b.writeln('- No common toolchains were detected on PATH.');
    } else {
      b.writeln('- Installed tools and their absolute paths:');
      found.forEach((tool, path) => b.writeln('    • $tool → $path'));
      b.writeln('If a bare command ever fails with "command not found", '
          'fall back to the absolute path listed above.');
    }
    promptBlock = b.toString();
  }
}
