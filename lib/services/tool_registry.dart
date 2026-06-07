import 'package:firebase_ai/firebase_ai.dart' as fbai;
import 'package:google_generative_ai/google_generative_ai.dart' as gai;

const String kSystemPrompt = '''
You are Arzu Code — an elite, token-frugal autonomous software engineer. Read only what's needed; edit surgically.

# RULES
- Greeting / general question → reply conversationally, no tools. Technical task → execute it fully with tools.
- NEVER end a turn by only describing a plan ("now I'll read X"): call that tool in the SAME response. Keep calling tools until the task is truly done.
- Finish ONLY by writing (no more tool calls) a short summary that ends with exactly: "Barcha vazifalar bajarildi!".
- If a command fails, read the error and fix it — max 3 tries on the same problem, then stop and ask the user.
- Reply in the user's language (Uzbek→Uzbek). One short sentence of intent before a tool batch; one line per error+fix; brief final summary. Never paste whole files into chat (the cards show them).
- When you build something viewable: start it with start_background_process (e.g. `python3 -m http.server 8123`), then CALL `open_url` with that URL so it actually opens in the browser (don't just print the link — the user asked you to OPEN it), and also print the link. For a single static .html with no server, you can open_url the file path directly.

# TOKENS (save the user money)
- Never re-read a file you already read. Explore with semantic_search / search_text / file_tree, not full reads; for big files use read_file offset+limit.
- Edit existing files with replace_in_file (cheapest: small unique old_string → new_string). Use write_file ONLY for a brand-new file — never rewrite a whole file to change a few lines. edit_file is a last resort.

# CODE QUALITY
- ⚠️ APOSTROPHES (#1 bug): Uzbek words (qo'shish, bo'yicha, o'chirish) break SINGLE-quoted Dart/JS strings. ALWAYS use double quotes — WRONG: Text('Qo'shish') → RIGHT: Text("Qo'shish").
- Create pubspec.yaml / package.json BEFORE pub get / npm install. Run `flutter create NAME` in the PARENT dir (avoid NAME/NAME).
- After writing Dart/JS, run the analyzer (flutter analyze / node --check) and fix every error before declaring done.
- NEVER scan the whole disk (find /, find ~, mdfind — blocked/slow). Use the HOST ENVIRONMENT paths below, or ask.

# FRESH INFO & MEDIA
- For anything possibly outdated (library versions, APIs, docs, current events), use web_search then fetch_url — don't guess.
- For icons/graphics use generate_image, save it, then wire it in via replace_in_file.''';

final _toolSpecs = [
  {
    'name': 'semantic_search',
    'desc': 'Search the codebase semantically using natural language (RAG Vector Search).',
    'params': {'query': {'type': 'string', 'desc': 'Natural language query.'}, 'cwd': {'type': 'string', 'desc': 'Working directory.'}},
    'optional': ['cwd']
  },
  {
    'name': 'list_dir',
    'desc': 'List the contents of a directory.',
    'params': {'path': {'type': 'string', 'desc': 'Absolute or ~ path to a directory.'}},
    'optional': <String>[]
  },
  {
    'name': 'read_file',
    'desc': 'Read a text file (with line numbers). Do NOT re-read files you already read. For large files, pass offset+limit to read only a line range.',
    'params': {
      'path': {'type': 'string', 'desc': 'Absolute or ~ path to the file.'},
      'offset': {'type': 'integer', 'desc': '1-based line to start from (optional).'},
      'limit': {'type': 'integer', 'desc': 'Max number of lines to read (optional).'},
    },
    'optional': ['offset', 'limit']
  },
  {
    'name': 'replace_in_file',
    'desc': 'PREFERRED edit tool (cheapest). Replace an exact unique snippet in a file. Provide a small unique old_string and its new_string. Use this instead of rewriting files.',
    'params': {
      'path': {'type': 'string', 'desc': 'Absolute or ~ path.'},
      'old_string': {'type': 'string', 'desc': 'Exact existing text to find (must be unique unless replace_all).'},
      'new_string': {'type': 'string', 'desc': 'Replacement text.'},
      'replace_all': {'type': 'boolean', 'desc': 'Replace every occurrence (default false).'},
    },
    'optional': ['replace_all']
  },
  {
    'name': 'write_file',
    'desc': 'Create a BRAND-NEW file. Never use this to rewrite an existing file in full — use replace_in_file instead.',
    'params': {'path': {'type': 'string', 'desc': 'Absolute or ~ path.'}, 'content': {'type': 'string', 'desc': 'Full file content.'}},
    'optional': <String>[]
  },
  {
    'name': 'edit_file',
    'desc': 'Last-resort line-range replace (1-based). Prefer replace_in_file; line numbers drift after edits.',
    'params': {'path': {'type': 'string', 'desc': 'Absolute or ~ path.'}, 'start_line': {'type': 'integer', 'desc': 'First line.'}, 'end_line': {'type': 'integer', 'desc': 'Last line.'}, 'replacement_text': {'type': 'string', 'desc': 'New code.'}},
    'optional': <String>[]
  },
  {
    'name': 'web_search',
    'desc': 'Search the web for CURRENT/up-to-date info (docs, versions, APIs, news). Returns top results with titles, URLs and snippets. Use this instead of guessing facts that may be outdated.',
    'params': {'query': {'type': 'string', 'desc': 'Search query.'}},
    'optional': <String>[]
  },
  {
    'name': 'fetch_url',
    'desc': 'Fetch a web page and return its readable text (HTML stripped). Use after web_search to read a specific result, or for a known docs URL.',
    'params': {'url': {'type': 'string', 'desc': 'The full http(s) URL.'}},
    'optional': <String>[]
  },
  {
    'name': 'open_url',
    'desc': 'Open a URL or a local file in the user\'s default browser. ALWAYS call this when the user asks to "open", "show", "run in Chrome", or after starting a local server — it actually opens the page for them.',
    'params': {'url': {'type': 'string', 'desc': 'http(s) URL (e.g. http://localhost:8123) or a local file path / file:// URL.'}},
    'optional': <String>[]
  },
  {
    'name': 'make_dir',
    'desc': 'Create a directory (recursively).',
    'params': {'path': {'type': 'string', 'desc': 'Absolute or ~ path.'}},
    'optional': <String>[]
  },
  {
    'name': 'path_exists',
    'desc': 'Check whether a path exists.',
    'params': {'path': {'type': 'string', 'desc': 'Absolute or ~ path.'}},
    'optional': <String>[]
  },
  {
    'name': 'search_text',
    'desc': 'Exact text match search within a directory tree.',
    'params': {'path': {'type': 'string', 'desc': 'Directory.'}, 'query': {'type': 'string', 'desc': 'Exact text.'}},
    'optional': <String>[]
  },
  {
    'name': 'run_command',
    'desc': 'Run a shell command with /bin/zsh.',
    'params': {'command': {'type': 'string', 'desc': 'The shell command.'}, 'cwd': {'type': 'string', 'desc': 'Working directory.'}},
    'optional': ['cwd']
  },
  {
    'name': 'create_project',
    'desc': 'Scaffold a new project directory.',
    'params': {'parent_dir': {'type': 'string', 'desc': 'Directory.'}, 'name': {'type': 'string', 'desc': 'Folder name.'}, 'kind': {'type': 'string', 'desc': 'node, web, flutter, python, generic.'}},
    'optional': <String>[]
  },
  {
    'name': 'file_tree',
    'desc': 'Show the directory structure as an ASCII tree.',
    'params': {'path': {'type': 'string', 'desc': 'Directory.'}, 'max_depth': {'type': 'integer', 'desc': 'Recursion depth.'}},
    'optional': ['path', 'max_depth']
  },
  {
    'name': 'download_asset',
    'desc': 'Download a file from a URL and save it into the project.',
    'params': {'url': {'type': 'string', 'desc': 'Remote URL.'}, 'save_path': {'type': 'string', 'desc': 'Path to save.'}},
    'optional': <String>[]
  },
  {
    'name': 'generate_image',
    'desc': 'Generate a brand-new image from a text prompt and save it.',
    'params': {'prompt': {'type': 'string', 'desc': 'Image description.'}, 'save_path': {'type': 'string', 'desc': 'Path to save the PNG.'}},
    'optional': <String>[]
  },
  {
    'name': 'start_background_process',
    'desc': 'Start a LONG-RUNNING command in the background.',
    'params': {'command': {'type': 'string', 'desc': 'Command to run.'}, 'cwd': {'type': 'string', 'desc': 'Working directory.'}, 'name': {'type': 'string', 'desc': 'Label.'}},
    'optional': ['cwd', 'name']
  },
  {
    'name': 'read_process_output',
    'desc': 'Read the latest stdout/stderr from a background process.',
    'params': {'id': {'type': 'string', 'desc': 'The process id.'}},
    'optional': <String>[]
  },
  {
    'name': 'list_processes',
    'desc': 'List all background processes.',
    'params': <String, dynamic>{},
    'optional': <String>[]
  },
  {
    'name': 'stop_process',
    'desc': 'Kill a background process by id.',
    'params': {'id': {'type': 'string', 'desc': 'The process id.'}},
    'optional': <String>[]
  }
];

List<fbai.FunctionDeclaration> buildVertexTools() {
  return _toolSpecs.map((spec) {
    final params = spec['params'] as Map<String, dynamic>;
    final props = <String, fbai.Schema>{};
    for (final e in params.entries) {
      final t = switch (e.value['type']) {
        'integer' => fbai.Schema.integer(description: e.value['desc']),
        'boolean' => fbai.Schema.boolean(description: e.value['desc']),
        _ => fbai.Schema.string(description: e.value['desc']),
      };
      props[e.key] = t;
    }
    return fbai.FunctionDeclaration(
      spec['name'] as String,
      spec['desc'] as String,
      parameters: props,
      optionalParameters: spec['optional'] as List<String>,
    );
  }).toList();
}

List<gai.FunctionDeclaration> buildGoogleAiTools() {
  return _toolSpecs.map((spec) {
    final params = spec['params'] as Map<String, dynamic>;
    final props = <String, gai.Schema>{};
    final requiredParams = <String>[];
    final optional = spec['optional'] as List<String>;

    for (final e in params.entries) {
      props[e.key] = switch (e.value['type']) {
        'integer' => gai.Schema.integer(description: e.value['desc']),
        'boolean' => gai.Schema.boolean(description: e.value['desc']),
        _ => gai.Schema.string(description: e.value['desc']),
      };
      if (!optional.contains(e.key)) requiredParams.add(e.key);
    }
    return gai.FunctionDeclaration(
      spec['name'] as String,
      spec['desc'] as String,
      gai.Schema.object(properties: props, requiredProperties: requiredParams.isNotEmpty ? requiredParams : null),
    );
  }).toList();
}

List<Map<String, dynamic>> buildOllamaTools() {
  return _toolSpecs.map((spec) {
    final params = spec['params'] as Map<String, dynamic>;
    final props = <String, dynamic>{};
    final req = <String>[];
    final opt = spec['optional'] as List<String>;
    for (final e in params.entries) {
      props[e.key] = {'type': e.value['type'], 'description': e.value['desc']};
      if (!opt.contains(e.key)) req.add(e.key);
    }
    return {
      "type": "function",
      "function": {"name": spec['name'], "description": spec['desc'], "parameters": {"type": "object", "properties": props, "required": req}}
    };
  }).toList();
}

/// Text protocol for cloud models that lack native tool-calling (e.g. gemma).
/// The model emits a single ```json {"name": "...", "arguments": {...}} ``` block
/// to call a tool, or plain prose when finished. AgentService parses that block.
String buildToolProtocolText() {
  final buf = StringBuffer();
  buf.writeln('\n\n# TOOL PROTOCOL (you have no native tool API — use this exactly):');
  buf.writeln('To use a tool, reply with ONE fenced json block and nothing else:');
  buf.writeln('```json');
  buf.writeln('{"name": "tool_name", "arguments": {"arg": "value"}}');
  buf.writeln('```');
  buf.writeln('After you get the tool result, decide the next step. When the task is done, reply in plain text with no json block.');
  buf.writeln('\nAvailable tools:');
  for (final spec in _toolSpecs) {
    final params = (spec['params'] as Map<String, dynamic>).keys.join(', ');
    buf.writeln('- ${spec['name']}(${params.isEmpty ? '' : params}): ${spec['desc']}');
  }
  return buf.toString();
}