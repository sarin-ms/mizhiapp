import 'package:flutter/material.dart';
import 'package:mizhi/utils/splash_screen.dart';
import 'package:mizhi/screens/permissions_screen.dart';
import 'package:mizhi/screens/home_screen.dart';
import 'package:mizhi/screens/street_smart_screen.dart';
import 'package:mizhi/screens/money_sense_screen.dart';
import 'package:mizhi/screens/settings_screen.dart';
import 'package:mizhi/screens/emergency_contact_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mizhi',
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
    );
  }
}
