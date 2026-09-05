import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'openrouter.dart';

/// User-configurable settings, stored on the device only.
///
/// The OpenRouter API key is a credential: it is kept in preferences, is
/// never written to a backup file or a log, and is sent only to
/// openrouter.ai.
class AppSettings {
  final String openRouterKey;
  final String openRouterModel;

  /// Look nutrition up automatically while a food is being typed. When off,
  /// the estimate button on the food form still works on demand.
  final bool autoEstimate;

  /// Force the pitch-black (AMOLED) dark theme instead of following system.
  final bool pitchBlack;

  const AppSettings({
    this.openRouterKey = '',
    this.openRouterModel = OpenRouterClient.defaultModel,
    this.autoEstimate = true,
    this.pitchBlack = false,
  });

  bool get hasKey => openRouterKey.trim().isNotEmpty;

  AppSettings copyWith({
    String? openRouterKey,
    String? openRouterModel,
    bool? autoEstimate,
    bool? pitchBlack,
  }) =>
      AppSettings(
        openRouterKey: openRouterKey ?? this.openRouterKey,
        openRouterModel: openRouterModel ?? this.openRouterModel,
        autoEstimate: autoEstimate ?? this.autoEstimate,
        pitchBlack: pitchBlack ?? this.pitchBlack,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyApi = 'openrouter.apiKey';
  static const _keyModel = 'openrouter.model';
  static const _keyAuto = 'openrouter.autoEstimate';

  /// Kept under its original name so the existing preference carries over.
  static const _keyPitchBlack = 'pitchBlack';

  static SharedPreferences? _prefs;

  /// Loads preferences before the app starts, so the first build already has
  /// the real values rather than defaults that flicker.
  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  AppSettings build() => AppSettings(
        openRouterKey: _prefs?.getString(_keyApi) ?? '',
        openRouterModel:
            _prefs?.getString(_keyModel) ?? OpenRouterClient.defaultModel,
        autoEstimate: _prefs?.getBool(_keyAuto) ?? true,
        pitchBlack: _prefs?.getBool(_keyPitchBlack) ?? false,
      );

  void setApiKey(String value) {
    final key = value.trim();
    state = state.copyWith(openRouterKey: key);
    _prefs?.setString(_keyApi, key);
  }

  void setModel(String id) {
    state = state.copyWith(openRouterModel: id);
    _prefs?.setString(_keyModel, id);
  }

  void setAutoEstimate(bool value) {
    state = state.copyWith(autoEstimate: value);
    _prefs?.setBool(_keyAuto, value);
  }

  void togglePitchBlack() {
    final value = !state.pitchBlack;
    state = state.copyWith(pitchBlack: value);
    _prefs?.setBool(_keyPitchBlack, value);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// An OpenRouter client for the configured key and model, or null when no
/// key has been entered yet.
final openRouterProvider = Provider<OpenRouterClient?>((ref) {
  final s = ref.watch(settingsProvider);
  if (!s.hasKey) return null;
  final client = OpenRouterClient(
    apiKey: s.openRouterKey.trim(),
    model: s.openRouterModel,
  );
  ref.onDispose(client.close);
  return client;
});
