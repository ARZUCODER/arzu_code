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

  final bool useLocalModel;
  final String localModel;

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
    this.localModel = 'qwen2.5-coder:3b',
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
      localModel: json['localModel'] as String? ?? 'qwen2.5-coder:3b',
      blockedCommandPatterns: (json['blockedCommandPatterns'] as List?)?.cast<String>() ?? const AppConfig().blockedCommandPatterns,
      alwaysAllow: (json['alwaysAllow'] as Map?)?.map((k, v) => MapEntry(k as String, v as bool)) ?? const {},
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
    );
  }
}

const kDefaultImageModel = 'gemini-2.5-flash-image';

const kVertexModels = <String>[
  'gemini-2.5-pro',
  'gemini-2.5-flash',
];

const kGoogleAiModels = <String>[
  'gemini-3.1-pro-preview',
  'gemini-3.5-flash',
  'gemini-3.1-flash-lite',
];

const kAvailableImageModels = <String>[
  'gemini-2.5-flash-image',
];

const kAvailableLocalModels = <String>[
  'qwen2.5-coder:3b',
  'gemma2:2b',
  'llama3.1:8b',
  'deepseek-coder-v2',
];