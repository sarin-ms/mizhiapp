import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mizhi/utils/alert_messages.dart';

/// Language display name → TTS locale code
const Map<String, String> languageCodes = {
  'English': 'en-IN',
  'Hindi': 'hi-IN',
  'Tamil': 'ta-IN',
  'Malayalam': 'ml-IN',
  'Telugu': 'te-IN',
};

/// Alert speed label → TTS speech rate
const Map<String, double> speedRates = {
  'Slow': 0.35,
  'Normal': 0.55,
  'Fast': 0.75,
};

/// Apply saved settings to a [FlutterTts] instance.
/// Also updates the global [kAlertCooldownSeconds].
Future<void> applyTtsSettings(FlutterTts tts) async {
  final prefs = await SharedPreferences.getInstance();

  final lang = prefs.getString('mizhi_language') ?? 'English';
  final speed = prefs.getString('mizhi_alert_speed') ?? 'Normal';
  final volume = prefs.getDouble('mizhi_volume') ?? 0.8;
  final cooldown = prefs.getInt('mizhi_cooldown') ?? 3;

  await tts.setLanguage(languageCodes[lang] ?? 'en-IN');
  await tts.setSpeechRate(speedRates[speed] ?? 0.55);
  await tts.setVolume(volume);

  kAlertCooldownSeconds = cooldown;
}

/// Read vibration preference (defaults to true).
Future<bool> loadVibrationPref() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('mizhi_vibration') ?? true;
}
