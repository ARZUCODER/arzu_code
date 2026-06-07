enum PermissionMode {
  ask,
  acceptEdits,
  auto,
}

extension PermissionModeX on PermissionMode {
  String get label => switch (this) {
    PermissionMode.ask => 'Ask every time',
    PermissionMode.acceptEdits => 'Auto-accept edits',
    PermissionMode.auto => 'Full auto',
  };

  String get short => switch (this) {
    PermissionMode.ask => 'Ask',
    PermissionMode.acceptEdits => 'Accept edits',
    PermissionMode.auto => 'Auto',
  };

  String get description => switch (this) {
    PermissionMode.ask => 'Arzu asks before writing files or running any command.',
    PermissionMode.acceptEdits => 'File writes/edits run automatically; shell commands still ask.',
    PermissionMode.auto => 'Everything runs automatically. Only the safety filter and allowed folders apply.',
  };
}

class AppConfig {
  final List<String> allowedFolders;
  final PermissionMode permissionMode;

  final String model;
  final String testModel;
  final bool testMode;

  final String imageModel;
  final List<String> customModels;
  final Map<String, String> customModelEngines;

  final String serviceAccountPath;
  final String googleApiKey;

  // "Local model" now means the Arzu Cloud (Gemma via Ollama on the droplet),
  // proxied through the ilm_ai backend. The JSON keys are kept for back-compat.
  final bool useLocalModel;
  final String localModel;

  // Arzu Cloud gateway (ilm_ai backend → Ollama). Lets us route gemma today and
  // qwen-coder tomorrow with zero client changes.
  final String arzuCloudUrl;
  final String arzuCloudKey;

  final List<String> blockedCommandPatterns;
  final Map<String, bool> alwaysAllow;
  final double temperature;

  const AppConfig({
    this.allowedFolders = const [],
    this.permissionMode = PermissionMode.ask,
    this.model = 'gemini-3.1-pro-preview',
    this.testModel = 'gemini-3.1-flash-lite',
    this.testMode = false,
    this.imageModel = 'gemini-2.5-flash-image',
    this.customModels = const [],
    this.customModelEngines = const {},
    this.serviceAccountPath = '',
    this.googleApiKey = '',
    this.useLocalModel = false,
    this.localModel = 'gemma4:31b-cloud',
    this.arzuCloudUrl = 'https://core.arzucoder.uz',
    this.arzuCloudKey = '',
    this.blockedCommandPatterns = const [
      'rm -rf /',
      'rm -rf ~',
      ':(){:|:&};:',
      'mkfs',
      'dd if=',
      '> /dev/sda',
      'sudo rm',
    ],
    this.alwaysAllow = const {},
    this.temperature = 0.7,
  });

  String get activeModel => useLocalModel
      ? localModel
      : (testMode ? testModel : model);

  AppConfig copyWith({
    List<String>? allowedFolders,
    PermissionMode? permissionMode,
    String? model,
    String? testModel,
    bool? testMode,
    String? imageModel,
    List<String>? customModels,
    Map<String, String>? customModelEngines,
    String? serviceAccountPath,
    String? googleApiKey,
    bool? useLocalModel,
    String? localModel,
    String? arzuCloudUrl,
    String? arzuCloudKey,
    List<String>? blockedCommandPatterns,
    Map<String, bool>? alwaysAllow,
    double? temperature,
  }) {
    return AppConfig(
      allowedFolders: allowedFolders ?? this.allowedFolders,
      permissionMode: permissionMode ?? this.permissionMode,
      model: model ?? this.model,
      testModel: testModel ?? this.testModel,
      testMode: testMode ?? this.testMode,
      imageModel: imageModel ?? this.imageModel,
      customModels: customModels ?? this.customModels,
      customModelEngines: customModelEngines ?? this.customModelEngines,
      serviceAccountPath: serviceAccountPath ?? this.serviceAccountPath,
      googleApiKey: googleApiKey ?? this.googleApiKey,
      useLocalModel: useLocalModel ?? this.useLocalModel,
      localModel: localModel ?? this.localModel,
      arzuCloudUrl: arzuCloudUrl ?? this.arzuCloudUrl,
      arzuCloudKey: arzuCloudKey ?? this.arzuCloudKey,
      blockedCommandPatterns: blockedCommandPatterns ?? this.blockedCommandPatterns,
      alwaysAllow: alwaysAllow ?? this.alwaysAllow,
      temperature: temperature ?? this.temperature,
    );
  }

  Map<String, dynamic> toJson() => {
    'allowedFolders': allowedFolders,
    'permissionMode': permissionMode.name,
    'model': model,
    'testModel': testModel,
    'testMode': testMode,
    'imageModel': imageModel,
    'customModels': customModels,
    'customModelEngines': customModelEngines,
    'serviceAccountPath': serviceAccountPath,
    'googleApiKey': googleApiKey,
    'useLocalModel': useLocalModel,
    'localModel': localModel,
    'arzuCloudUrl': arzuCloudUrl,
    'arzuCloudKey': arzuCloudKey,
    'blockedCommandPatterns': blockedCommandPatterns,
    'alwaysAllow': alwaysAllow,
    'temperature': temperature,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      allowedFolders: (json['allowedFolders'] as List?)?.cast<String>() ?? const [],
      permissionMode: PermissionMode.values.firstWhere(
            (m) => m.name == json['permissionMode'],
        orElse: () => PermissionMode.ask,
      ),
      model: json['model'] as String? ?? 'gemini-3.1-pro-preview',
      testModel: json['testModel'] as String? ?? 'gemini-3.1-flash-lite',
      testMode: json['testMode'] as bool? ?? false,
      imageModel: json['imageModel'] as String? ?? 'gemini-2.5-flash-image',
      customModels: (json['customModels'] as List?)?.cast<String>() ?? const [],
      customModelEngines: (json['customModelEngines'] as Map?)?.cast<String, String>() ?? const {},
      serviceAccountPath: json['serviceAccountPath'] as String? ?? '',
      googleApiKey: json['googleApiKey'] as String? ?? '',
      useLocalModel: json['useLocalModel'] as bool? ?? false,
      localModel: json['localModel'] as String? ?? 'gemma4:31b-cloud',
      arzuCloudUrl: json['arzuCloudUrl'] as String? ?? 'https://core.arzucoder.uz',
      arzuCloudKey: json['arzuCloudKey'] as String? ?? '',
      blockedCommandPatterns: (json['blockedCommandPatterns'] as List?)?.cast<String>() ?? const AppConfig().blockedCommandPatterns,
      alwaysAllow: (json['alwaysAllow'] as Map?)?.map((k, v) => MapEntry(k as String, v as bool)) ?? const {},
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
    );
  }
}

const kDefaultImageModel = 'gemini-2.5-flash-image';

const kVertexModels = <String>[
  'gemini-3.1-pro-preview', // strongest — via Vertex (your billing, no Ollama limit, 1M ctx)
  'gemini-2.5-pro',
  'gemini-2.5-flash',
];

const kGoogleAiModels = <String>[
  'gemini-3.5-flash',
  'gemini-3.1-flash-lite',
];

const kAvailableImageModels = <String>[
  'gemini-2.5-flash-image',
];

// Models served by the Arzu Cloud gateway (ilm_ai backend → Ollama on the droplet).
// gemma4 is live today; add tool-capable coder models (e.g. qwen2.5-coder) here
// once they are pulled on the server — no other client change needed.
const kArzuCloudModels = <String>[
  'qwen3-coder:480b-cloud', // strongest agentic coder (native tools, 256K ctx)
  'qwen3.5:397b-cloud',     // newest flagship (tools+thinking+vision) — needs an Ollama subscription
  'gemma4:31b-cloud',       // free fallback, weaker at multi-step tool use
];

// "Claude CLI" engine: the chat runs the real `claude` (Claude Code) binary in
// headless print mode, driven by an Ollama model. Format: 'claude-cli:<ollamaModel>'.
const kClaudeCliPrefix = 'claude-cli:';
const kClaudeCliModels = <String>[
  'claude-cli:qwen3-coder:480b-cloud',
  'claude-cli:gemma4:31b-cloud',
];
bool isClaudeCliModel(String model) => model.startsWith(kClaudeCliPrefix);
String claudeCliOllamaModel(String model) => model.substring(kClaudeCliPrefix.length);

// Models that support Ollama's native structured tool-calling. Everything else
// (e.g. gemma) falls back to the text/JSON tool protocol embedded in the prompt.
bool cloudModelSupportsNativeTools(String model) {
  final m = model.toLowerCase();
  return m.contains('qwen') || m.contains('coder') || m.contains('llama3.1') || m.contains('mistral');
}