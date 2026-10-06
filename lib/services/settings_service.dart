import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'card_cycle.dart';
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

  /// Whether the chosen model accepts images, recorded when it is picked so
  /// photo logging can warn before sending a photo somewhere it cannot go.
  /// Unknown for a model that predates this setting, which is treated as
  /// "try it and report what happens".
  final bool? modelAcceptsImages;

  /// Number to dial for voicemail, when the SIM's own value is wrong or
  /// missing. Empty means use whatever the SIM reports.
  final String voicemailNumber;

  /// Force the pitch-black (AMOLED) dark theme instead of following system.
  final bool pitchBlack;

  /// Day of the month the credit card statement closes. Zero bills the
  /// card by calendar month instead.
  final int cardStatementDay;

  /// Day of the month the card bill is paid.
  final int cardDueDay;

  const AppSettings({
    this.openRouterKey = '',
    this.openRouterModel = OpenRouterClient.defaultModel,
    this.autoEstimate = true,
    this.modelAcceptsImages,
    this.voicemailNumber = '',
    this.pitchBlack = false,
    this.cardStatementDay = 25,
    this.cardDueDay = 15,
  });

  bool get hasKey => openRouterKey.trim().isNotEmpty;

  /// How card spending is divided into bills.
  CardCycle get cardCycle =>
      CardCycle(closingDay: cardStatementDay, dueDay: cardDueDay);

  AppSettings copyWith({
    String? openRouterKey,
    String? openRouterModel,
    bool? autoEstimate,
    bool? modelAcceptsImages,
    bool clearModelAcceptsImages = false,
    String? voicemailNumber,
    bool? pitchBlack,
    int? cardStatementDay,
    int? cardDueDay,
  }) =>
      AppSettings(
        openRouterKey: openRouterKey ?? this.openRouterKey,
        openRouterModel: openRouterModel ?? this.openRouterModel,
        autoEstimate: autoEstimate ?? this.autoEstimate,
        modelAcceptsImages: clearModelAcceptsImages
            ? null
            : (modelAcceptsImages ?? this.modelAcceptsImages),
        voicemailNumber: voicemailNumber ?? this.voicemailNumber,
        pitchBlack: pitchBlack ?? this.pitchBlack,
        cardStatementDay: cardStatementDay ?? this.cardStatementDay,
        cardDueDay: cardDueDay ?? this.cardDueDay,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyApi = 'openrouter.apiKey';
  static const _keyModel = 'openrouter.model';
  static const _keyAuto = 'openrouter.autoEstimate';

  static const _keyVision = 'openrouter.modelAcceptsImages';
  static const _keyVoicemail = 'phone.voicemailNumber';

  /// Kept under its original name so the existing preference carries over.
  static const _keyPitchBlack = 'pitchBlack';

  static const _keyStatementDay = 'card.statementDay';
  static const _keyDueDay = 'card.dueDay';

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
        modelAcceptsImages: _prefs?.getBool(_keyVision),
        voicemailNumber: _prefs?.getString(_keyVoicemail) ?? '',
        pitchBlack: _prefs?.getBool(_keyPitchBlack) ?? false,
        cardStatementDay: _prefs?.getInt(_keyStatementDay) ?? 25,
        cardDueDay: _prefs?.getInt(_keyDueDay) ?? 15,
      );

  void setApiKey(String value) {
    final key = value.trim();
    state = state.copyWith(openRouterKey: key);
    _prefs?.setString(_keyApi, key);
  }

  /// [acceptsImages] comes from the model list when a model is picked
  /// there; null means it was set some other way and is not known.
  void setModel(String id, {bool? acceptsImages}) {
    state = state.copyWith(
      openRouterModel: id,
      modelAcceptsImages: acceptsImages,
      clearModelAcceptsImages: acceptsImages == null,
    );
    _prefs?.setString(_keyModel, id);
    if (acceptsImages == null) {
      _prefs?.remove(_keyVision);
    } else {
      _prefs?.setBool(_keyVision, acceptsImages);
    }
  }

  void setAutoEstimate(bool value) {
    state = state.copyWith(autoEstimate: value);
    _prefs?.setBool(_keyAuto, value);
  }

  void setVoicemailNumber(String value) {
    final number = value.trim();
    state = state.copyWith(voicemailNumber: number);
    _prefs?.setString(_keyVoicemail, number);
  }

  /// [day] is the day of the month the statement closes, or zero to bill
  /// the card by calendar month.
  void setCardStatementDay(int day) {
    final value = day < 0 ? 0 : (day > CardCycle.maxDay ? 0 : day);
    state = state.copyWith(cardStatementDay: value);
    _prefs?.setInt(_keyStatementDay, value);
  }

  void setCardDueDay(int day) {
    final value = day.clamp(1, CardCycle.maxDay);
    state = state.copyWith(cardDueDay: value);
    _prefs?.setInt(_keyDueDay, value);
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
