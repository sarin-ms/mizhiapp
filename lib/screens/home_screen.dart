import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mizhi/l10n/app_localizations.dart';
import 'package:mizhi/services/app_voice_service.dart';
import 'package:mizhi/services/app_audio.dart';

import 'package:mizhi/utils/settings_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AppAudio _flutterTts = AppAudio.instance;
  String? _focusedButton;
  Future<void> _handleButtonTap(
    String buttonId,
    String spokenText,
    Future<void> Function() action,
  ) async {
    if (_focusedButton == buttonId) {
      setState(() {
        _focusedButton = null;
      });
      await _flutterTts.stop();
      await action();
    } else {
      setState(() {
        _focusedButton = buttonId;
      });
      await _flutterTts.stop();
      await _flutterTts.speak(spokenText);

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _focusedButton == buttonId) {
          setState(() {
            _focusedButton = null;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await applyTtsSettings(_flutterTts);
    if (!mounted) return;
    await _flutterTts.say(
      'Welcome to Mizhi. Tap Street Smart or Money Sense to begin.',
    );
  }

  Future<void> _navigateWithVoicePause(String routeName) =>
      AppVoiceService.instance.navigate(routeName);

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return "Good morning";
    } else if (hour < 17) {
      return "Good afternoon";
    } else {
      return "Good evening";
    }
  }

  Widget _buildModeCard({
    required Color bgColor,
    required Color borderColor,
    required String imagePath,
    required String title,
    required String subtitle,
    required Color subtitleColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        width: double.infinity,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withValues(alpha: 0.2),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 28.0,
              vertical: 16.0,
            ),
            child: Row(
              children: [
                Image.asset(
                  imagePath,
                  width: 64,
                  height: 64,
                  cacheWidth: (64 * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(color: subtitleColor, fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Home screen should not be exited with back button
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.only(
                  left: 24.0,
                  right: 24.0,
                  top: 16.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          context.tr("MIZHI"),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _handleButtonTap(
                          'settings',
                          'Settings Menu',
                          () => _navigateWithVoicePause('/settings'),
                        );
                      },
                      child: Icon(
                        Icons.settings,
                        color: _focusedButton == 'settings'
                            ? const Color(0xFF00D4AA)
                            : Colors.white,
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      // Greeting
                      Text(
                        context.tr(_getGreeting()),
                        style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Help text
                      Text(
                        context.tr("How can I help you today?"),
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 32),

                      // Street Smart
                      _buildModeCard(
                        bgColor: const Color(0xFF8B6914),
                        borderColor: _focusedButton == 'street_smart'
                            ? Colors.white
                            : const Color(0xFFD4AF37),
                        imagePath: 'assets/images/Walking.png',
                        title: context.tr("STREET SMART"),
                        subtitle: context.tr("Detect obstacles"),
                        subtitleColor: Colors.white70,
                        onTap: () {
                          _handleButtonTap(
                            'street_smart',
                            'Street Smart mode',
                            () => _navigateWithVoicePause('/street-smart'),
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // Money Sense
                      _buildModeCard(
                        bgColor: const Color(0xFF8B6914),
                        borderColor: _focusedButton == 'money_sense'
                            ? Colors.white
                            : const Color(0xFFD4AF37),
                        imagePath: 'assets/images/Rupee.png',
                        title: context.tr("MONEY SENSE"),
                        subtitle: context.tr("Identify currency"),
                        subtitleColor: Colors.white70,
                        onTap: () {
                          _handleButtonTap(
                            'money_sense',
                            'Money sense mode',
                            () => _navigateWithVoicePause('/money-sense'),
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // Emergency Contact button
                      _buildModeCard(
                        bgColor: const Color(0xCC4A1A1A),
                        borderColor: _focusedButton == 'emergency_contact'
                            ? Colors.white
                            : const Color(0xFFCC4444),
                        imagePath: 'assets/images/Call.png',
                        title: context.tr("EMERGENCY CONTACT"),
                        subtitle: context.tr(""),
                        subtitleColor: Colors.transparent,
                        onTap: () {
                          _handleButtonTap(
                            'emergency_contact',
                            'Emergency contact',
                            () => _navigateWithVoicePause('/emergency-contact'),
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
