import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../services/config_store.dart';
import '../services/permissions_service.dart';

final permissionsServiceProvider = Provider<PermissionsService>((ref) {
  return PermissionsService(const AppConfig());
});

final configControllerProvider = StateNotifierProvider<ConfigController, AppConfig>((ref) {
  final perms = ref.watch(permissionsServiceProvider);
  return ConfigController(perms)..init();
});

class ConfigController extends StateNotifier<AppConfig> {
  final PermissionsService _perms;
  final _store = ConfigStore();

  ConfigController(this._perms) : super(const AppConfig());

  Future<void> init() async {
    final cfg = await _store.load();
    _apply(cfg);
  }

  void _apply(AppConfig cfg) {
    state = cfg;
    _perms.config = cfg;
    _store.save(cfg);
  }

  void addFolder(String path) {
    if (state.allowedFolders.contains(path)) return;
    _apply(state.copyWith(allowedFolders: [...state.allowedFolders, path]));
  }

  void removeFolder(String path) {
    _apply(state.copyWith(allowedFolders: state.allowedFolders.where((f) => f != path).toList()));
  }

  void setMode(PermissionMode mode) => _apply(state.copyWith(permissionMode: mode));

  void setModel(String model) => _apply(state.copyWith(model: model));

  void setTestModel(String model) => _apply(state.copyWith(testModel: model));

  void setTestMode(bool on) => _apply(state.copyWith(testMode: on, useLocalModel: false));

  void setUseLocalModel(bool on) => _apply(state.copyWith(useLocalModel: on, testMode: false));

  void setLocalModel(String model) => _apply(state.copyWith(localModel: model));

  void setArzuCloudUrl(String url) => _apply(state.copyWith(arzuCloudUrl: url.trim()));

  void setArzuCloudKey(String key) => _apply(state.copyWith(arzuCloudKey: key.trim()));

  void setImageModel(String model) => _apply(state.copyWith(imageModel: model));

  void setServiceAccountPath(String path) => _apply(state.copyWith(serviceAccountPath: path));

  void setGoogleApiKey(String key) => _apply(state.copyWith(googleApiKey: key));

  void setTemperature(double t) => _apply(state.copyWith(temperature: t));

  void addCustomModel(String model, String engine) {
    final id = model.trim();
    if (id.isEmpty) return;
    final known = kVertexModels.contains(id) || kGoogleAiModels.contains(id) || state.customModels.contains(id);

    final newEngines = Map<String, String>.from(state.customModelEngines);
    newEngines[id] = engine;

    _apply(state.copyWith(
      customModels: known && state.customModels.contains(id) ? state.customModels : [...state.customModels, id],
      customModelEngines: newEngines,
      model: id,
      testMode: false,
      useLocalModel: false,
    ));
  }

  void removeCustomModel(String model) {
    final newEngines = Map<String, String>.from(state.customModelEngines)..remove(model);
    _apply(state.copyWith(
      customModels: state.customModels.where((m) => m != model).toList(),
      customModelEngines: newEngines,
      model: state.model == model ? 'gemini-3.5-flash' : state.model,
    ));
  }

  void allowAlways(String signature) {
    _apply(state.copyWith(alwaysAllow: {...state.alwaysAllow, signature: true}));
  }

  void clearAlwaysAllow() => _apply(state.copyWith(alwaysAllow: {}));

  void setBlockedPatterns(List<String> patterns) => _apply(state.copyWith(blockedCommandPatterns: patterns));
}