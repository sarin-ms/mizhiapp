import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mizhi/l10n/app_localizations.dart';
import 'package:mizhi/l10n/language_catalog.dart';
import 'package:mizhi/screens/home_screen.dart';
import 'package:mizhi/screens/settings_screen.dart';
import 'package:mizhi/services/app_audio.dart';
import 'package:mizhi/services/app_settings.dart';

Widget localizedApp(Widget home) => AnimatedBuilder(
  animation: AppSettings.instance,
  builder: (_, child) => MaterialApp(
    locale: AppSettings.instance.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  ),
);

void main() {
  const tts = MethodChannel('flutter_tts');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          tts,
          (call) async => call.method == 'isLanguageAvailable' ? true : 1,
        );
    await AppSettings.instance.load();
  });
  tearDown(() async {
    await AppAudio.instance.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tts, null);
  });

  for (final language in languageCodes.keys) {
    testWidgets('Home labels render in $language at phone width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AppSettings.instance.save('mizhi_language', language);
      await tester.pumpWidget(localizedApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text(translate('STREET SMART', language)), findsOneWidget);
      expect(find.text(translate('MONEY SENSE', language)), findsOneWidget);
      expect(
        find.text(translate('Detect obstacles', language)),
        findsOneWidget,
      );
      expect(
        find.text(translate('How can I help you today?', language)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'Settings language picker changes the entire screen immediately',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(localizedApp(const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('SETTINGS'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('தமிழ்').last);
      await tester.pumpAndSettle();
      expect(find.text(translate('SETTINGS', 'Tamil')), findsOneWidget);
      expect(find.text(translate('Voice Volume', 'Tamil')), findsOneWidget);
      expect(find.text('Voice Volume'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getString('mizhi_language'),
        'Tamil',
      );
      expect(tester.takeException(), isNull);
      for (final language in ['Hindi', 'Malayalam', 'Telugu']) {
        await AppSettings.instance.save('mizhi_language', language);
        await tester.pumpAndSettle();
        expect(find.text(translate('SETTINGS', language)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
