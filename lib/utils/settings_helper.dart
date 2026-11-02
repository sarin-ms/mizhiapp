import 'package:mizhi/services/app_audio.dart';
import 'package:mizhi/services/app_settings.dart';

export 'package:mizhi/l10n/language_catalog.dart' show languageCodes;
export 'package:mizhi/services/app_audio.dart' show speedRates;

Future<void> applyTtsSettings(AppAudio audio) => audio.configure();
Future<bool> loadVibrationPref() async => AppSettings.instance.vibration;
