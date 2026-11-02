import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mizhi/l10n/language_catalog.dart';
import 'package:mizhi/services/app_settings.dart';

class AppLocalizations {
  final String language;
  const AppLocalizations(this.language);
  static const delegate = _AppLocalizationsDelegate();
  static final supportedLocales = languageCodes.values
      .map((code) => Locale(code.split('-').first, 'IN'))
      .toList();
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      AppLocalizations(AppSettings.instance.language);
  String text(String key, [Map<String, Object> parameters = const {}]) =>
      translate(key, language, parameters);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => languageCodes.values.any(
    (code) => code.split('-').first == locale.languageCode,
  );
  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(
    AppLocalizations(
      languageCodes.entries
          .firstWhere((e) => e.value.split('-').first == locale.languageCode)
          .key,
    ),
  );
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension LocalizedContext on BuildContext {
  String tr(String key, [Map<String, Object> parameters = const {}]) =>
      AppLocalizations.of(this).text(key, parameters);
}
