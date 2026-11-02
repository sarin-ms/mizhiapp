import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mizhi/l10n/language_catalog.dart';
import 'package:mizhi/utils/alert_messages.dart';

class AppSettings extends ChangeNotifier {
  static final instance = AppSettings();
  SharedPreferences? _preferences;
  String language = 'English';
  String alertSpeed = 'Normal';
  double volume = 0.8;
  bool vibration = true;
  bool voiceFeedback = true;
  int cooldown = 3;

  Locale get locale => Locale(languageCodes[language]!.split('-').first, 'IN');

  Future<void> load() async {
    final preferences = _preferences = await SharedPreferences.getInstance();
    final savedLanguage = preferences.getString('mizhi_language');
    language = languageCodes.containsKey(savedLanguage)
        ? savedLanguage!
        : 'English';
    alertSpeed = preferences.getString('mizhi_alert_speed') ?? 'Normal';
    volume = (preferences.getDouble('mizhi_volume') ?? 0.8).clamp(0.0, 1.0);
    vibration = preferences.getBool('mizhi_vibration') ?? true;
    voiceFeedback = preferences.getBool('mizhi_voice_feedback') ?? true;
    cooldown = (preferences.getInt('mizhi_cooldown') ?? 3).clamp(1, 10);
    kAlertCooldownSeconds = cooldown;
    notifyListeners();
  }

  Future<void> save(String key, Object value) async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    switch (key) {
      case 'mizhi_language':
        if (value is! String || !languageCodes.containsKey(value)) {
          throw ArgumentError('Unsupported language');
        }
        language = value;
      case 'mizhi_alert_speed':
        if (!['Slow', 'Normal', 'Fast'].contains(value)) {
          throw ArgumentError('Unsupported speed');
        }
        alertSpeed = value as String;
      case 'mizhi_volume':
        volume = (value as num).toDouble().clamp(0.0, 1.0);
        value = volume;
      case 'mizhi_vibration':
        vibration = value as bool;
      case 'mizhi_voice_feedback':
        voiceFeedback = value as bool;
      case 'mizhi_cooldown':
        cooldown = (value as int).clamp(1, 10);
        value = cooldown;
        kAlertCooldownSeconds = cooldown;
    }
    if (value is String) await preferences.setString(key, value);
    if (value is double) await preferences.setDouble(key, value);
    if (value is bool) await preferences.setBool(key, value);
    if (value is int) await preferences.setInt(key, value);
    notifyListeners();
  }
}
