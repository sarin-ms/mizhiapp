import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mizhi/l10n/language_catalog.dart';
import 'package:mizhi/services/app_settings.dart';

const speedRates = {'Slow': 0.35, 'Normal': 0.55, 'Fast': 0.75};

/// One speech engine and one selected locale for all screens and announcements.
class AppAudio extends ChangeNotifier {
  static final instance = AppAudio();
  final FlutterTts _engine;
  final AppSettings settings;
  Future<void> Function(String text)? beforeSpeak;
  VoidCallback? afterSpeak;
  bool speaking = false;
  bool voiceUnavailable = false;
  int _generation = 0;
  String? _configurationKey;
  Future<void>? _configuration;

  AppAudio({FlutterTts? engine, AppSettings? settings})
    : _engine = engine ?? FlutterTts(),
      settings = settings ?? AppSettings.instance;

  Future<void> configure({bool force = false}) async {
    final key =
        '${settings.language}:${settings.alertSpeed}:${settings.volume}';
    if (!force && _configurationKey == key) {
      await _configuration;
      return;
    }
    _configurationKey = key;
    final language = settings.language;
    final rate = speedRates[settings.alertSpeed] ?? 0.55;
    final volume = settings.volume;
    final previous = _configuration ?? Future<void>.value();
    _configuration = previous.then((_) async {
      if (_configurationKey == key) {
        await _configure(language, rate, volume, key);
      }
    });
    await _configuration;
  }

  Future<void> _configure(
    String language,
    double rate,
    double volume,
    String key,
  ) async {
    try {
      final code = languageCodes[language]!;
      final supported = await _engine.isLanguageAvailable(code);
      voiceUnavailable = supported != true && supported != 1;
      if (!voiceUnavailable) await _engine.setLanguage(code);
      await _engine.setSpeechRate(rate);
      await _engine.setVolume(volume);
      await _engine.awaitSpeakCompletion(true);
    } catch (e) {
      voiceUnavailable = true;
      if (_configurationKey == key) _configurationKey = null;
      debugPrint('Audio configuration error: $e');
    }
    notifyListeners();
  }

  Future<void> speak(String text, {bool force = false}) async {
    if ((!settings.voiceFeedback && !force) ||
        settings.volume == 0 ||
        text.isEmpty) {
      return;
    }
    final generation = ++_generation;
    speaking = true;
    notifyListeners();
    try {
      await beforeSpeak?.call(text);
      await configure();
      if (generation != _generation || voiceUnavailable) return;
      await _engine.speak(translate(text, settings.language));
    } catch (e) {
      debugPrint('Speech output error: $e');
    } finally {
      if (generation == _generation) {
        speaking = false;
        notifyListeners();
        afterSpeak?.call();
      }
    }
  }

  Future<void> say(String key, [Map<String, Object> parameters = const {}]) =>
      speak(translate(key, settings.language, parameters));

  Future<void> stop() async {
    final generation = ++_generation;
    try {
      await _engine.stop();
    } catch (e) {
      debugPrint('Stop speech error: $e');
    }
    if (generation == _generation) {
      speaking = false;
      notifyListeners();
      afterSpeak?.call();
    }
  }
}
