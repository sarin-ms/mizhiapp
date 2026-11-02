import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mizhi/utils/splash_screen.dart';
import 'package:mizhi/screens/permissions_screen.dart';
import 'package:mizhi/screens/home_screen.dart';
import 'package:mizhi/screens/street_smart_screen.dart';
import 'package:mizhi/screens/money_sense_screen.dart';
import 'package:mizhi/screens/settings_screen.dart';
import 'package:mizhi/screens/emergency_contact_screen.dart';
import 'package:mizhi/l10n/app_localizations.dart';
import 'package:mizhi/services/app_settings.dart';
import 'package:mizhi/services/app_voice_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _locale = ValueNotifier(AppSettings.instance.locale);
  void _settingsChanged() {
    _locale.value = AppSettings.instance.locale;
  }

  @override
  void initState() {
    super.initState();
    appRouteObserver.reset();
    AppSettings.instance.addListener(_settingsChanged);
    AppVoiceService.instance.start();
  }

  @override
  void dispose() {
    AppVoiceService.instance.shutdown();
    AppSettings.instance.removeListener(_settingsChanged);
    _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: _locale,
      builder: (context, locale, _) => MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [appRouteObserver],
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        onGenerateTitle: (context) => context.tr('Mizhi'),
        builder: (context, child) => Column(
          children: [
            Expanded(child: child!),
            const VoiceControlBar(),
          ],
        ),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00D4AA)),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/permissions': (context) => const PermissionsScreen(),
          '/home': (context) => const HomeScreen(),
          '/street-smart': (context) => const StreetSmartScreen(),
          '/money-sense': (context) => const MoneySenseScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/emergency-contact': (context) => const EmergencyContactScreen(),
        },
      ),
    );
  }
}
