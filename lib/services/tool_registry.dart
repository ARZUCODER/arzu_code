import 'package:firebase_ai/firebase_ai.dart' as fbai;
import 'package:google_generative_ai/google_generative_ai.dart' as gai;

const String kSystemPrompt = '''
You are Arzu Code — an Elite Autonomous AI Software Engineer.

# BEHAVIOR:
- If the user simply says "Hello" or asks a general question, just reply conversationally. DO NOT trigger tools unless you are asked to write code, inspect files, or run commands.
- If the user assigns a technical task, EXECUTE IT fully using the tools provided.
- If a command fails, READ the error, FIX the bug yourself, and RETRY. You are autonomous.
- Do not stop until the task is complete. If you call a tool, wait for the result and proceed.
- Once a task is 100% complete, summarize what you did and say "Barcha vazifalar bajarildi!".

# MEDIA & IMAGES:
- If the user asks for icons or graphics, use `generate_image` and save it to the project (e.g., `assets/logo.png`), then update `pubspec.yaml` and the code to display it.

Keep your chat responses concise. Speak mainly through tool actions.
''';

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
    'desc': 'Read a text file. Returns the content with line numbers. Always use this before editing a file.',
    'params': {'path': {'type': 'string', 'desc': 'Absolute or ~ path to the file.'}},
    'optional': <String>[]
  },
  {
    'name': 'write_file',
    'desc': 'Create a new file or completely overwrite an existing one.',
    'params': {'path': {'type': 'string', 'desc': 'Absolute or ~ path.'}, 'content': {'type': 'string', 'desc': 'Full file content.'}},
    'optional': <String>[]
  },
  {
    'name': 'edit_file',
    'desc': 'Surgically replace a range of lines in an existing file using 1-based line numbers.',
    'params': {'path': {'type': 'string', 'desc': 'Absolute or ~ path.'}, 'start_line': {'type': 'integer', 'desc': 'First line.'}, 'end_line': {'type': 'integer', 'desc': 'Last line.'}, 'replacement_text': {'type': 'string', 'desc': 'New code.'}},
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
      final t = e.value['type'] == 'integer'
          ? fbai.Schema.integer(description: e.value['desc'])
          : fbai.Schema.string(description: e.value['desc']);
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
      if (e.value['type'] == 'integer') {
        props[e.key] = gai.Schema.integer(description: e.value['desc']);
      } else {
        props[e.key] = gai.Schema.string(description: e.value['desc']);
      }
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