enum ToolStatus { pending, approved, denied, running, done, error }

class ToolResult {
  final bool ok;
  final String? output;
  final String? error;

  const ToolResult({required this.ok, this.output, this.error});

  String get display => ok ? (output ?? 'Done') : (error ?? 'Error');

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'output': output,
    'error': error,
  };

  factory ToolResult.fromJson(Map<String, dynamic> json) => ToolResult(
    ok: json['ok'] as bool? ?? false,
    output: json['output'] as String?,
    error: json['error'] as String?,
  );
}

class ToolCall {
  final String id;
  final String name;
  final Map<String, Object?> args;
  ToolStatus status;
  ToolResult? result;

  final DateTime startedAt;
  DateTime? completedAt;

  ToolCall({
    required this.id,
    required this.name,
    required this.args,
    this.status = ToolStatus.pending,
    this.result,
    DateTime? startedAt,
    this.completedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  bool get isMutating => kMutatingTools.contains(name);

  String get ruleSignature {
    if (name == 'run_command') {
      final cmd = (args['command'] as String? ?? '').trim();
      final first = cmd.split(RegExp(r'\s+')).first;
      return 'run_command:$first';
    }
    return name;
  }

  String get summary {
    switch (name) {
      case 'semantic_search':
        return 'AI Search: "${args['query']}"';
      case 'read_file':
        return 'Read ${args['path']}';
      case 'write_file':
        return 'Write ${args['path']}';
      case 'edit_file':
        return 'Edit ${args['path']}';
      case 'make_dir':
        return 'Create folder ${args['path']}';
      case 'list_dir':
        return 'List ${args['path']}';
      case 'path_exists':
        return 'Check ${args['path']}';
      case 'search_text':
        return 'Search "${args['query']}" in ${args['path']}';
      case 'run_command':
        return '\$ ${args['command']}';
      case 'create_project':
        return 'Scaffold ${args['kind']} project "${args['name']}"';
      case 'file_tree':
        return 'Tree ${args['path'] ?? '(workspace)'}';
      case 'download_asset':
        return 'Download → ${args['save_path']}';
      case 'generate_image':
        return 'Generate image → ${args['save_path']}';
      case 'start_background_process':
        return 'Run (bg) \$ ${args['command']}';
      case 'read_process_output':
        return 'Read logs of ${args['id']}';
      case 'list_processes':
        return 'List background processes';
      case 'stop_process':
        return 'Stop process ${args['id']}';
      default:
        return name;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'args': args,
    'status': status.name,
    'result': result?.toJson(),
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      args: Map<String, Object?>.from(json['args'] as Map? ?? {}),
      status: ToolStatus.values.firstWhere(
            (e) => e.name == json['status'],
        orElse: () => ToolStatus.pending,
      ),
      result: json['result'] != null
          ? ToolResult.fromJson(Map<String, dynamic>.from(json['result']))
          : null,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'])
          : DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }
}

const kMutatingTools = <String>{
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