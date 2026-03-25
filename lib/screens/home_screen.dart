import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mizhi/utils/settings_helper.dart';
import 'package:mizhi/utils/localization.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  String? _focusedButton;
  bool _isListening = false;
  bool _speechReady = false;
  bool _allowListening = true;
  Timer? _restartListenTimer;
  static const Duration _restartListeningDelay = Duration(seconds: 2);
  DateTime _lastVoiceCommandAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _voiceCommandCooldown = Duration(seconds: 4);

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
    _initSpeech();
  }

  Future<void> _initTts() async {
    await applyTtsSettings(_flutterTts);
    final lang = await currentLanguage();
    final welcome = welcomeMessages[lang] ?? welcomeMessages['English']!;
    await Future.delayed(const Duration(seconds: 1));
    await _flutterTts.speak(welcome);
  }

  Future<void> _initSpeech() async {
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
          _scheduleListeningRestart();
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isListening = false);
        _scheduleListeningRestart();
      },
    );

    if (_speechReady) {
      _startListening();
    }
  }

  void _scheduleListeningRestart() {
    if (!mounted || !_speechReady || _isListening || !_allowListening) return;
    if (_restartListenTimer?.isActive ?? false) return;

    _restartListenTimer = Timer(_restartListeningDelay, () {
      if (!mounted) return;
      _startListening();
    });
  }

  Future<void> _startListening() async {
    if (!mounted || !_speechReady || _isListening || !_allowListening) return;
    _restartListenTimer?.cancel();
    await _speech.listen(
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: _onSpeechResult,
    );
    if (mounted) {
      setState(() => _isListening = _speech.isListening);
    }
  }

  Future<void> _setListeningEnabled(bool enabled) async {
    _allowListening = enabled;

    if (!enabled) {
      _restartListenTimer?.cancel();
      if (_speech.isListening) {
        await _speech.stop();
      }
      if (mounted) {
        setState(() => _isListening = false);
      }
      return;
    }

    await _startListening();
  }

  Future<void> _navigateWithVoicePause(String routeName) async {
    await _setListeningEnabled(false);
    if (!mounted) return;
    await Navigator.pushNamed(context, routeName);
    if (!mounted) return;
    await _setListeningEnabled(true);
  }

  Future<void> _onSpeechResult(SpeechRecognitionResult result) async {
    final spoken = result.recognizedWords.trim().toLowerCase();
    if (spoken.isEmpty) return;

    final normalized = spoken.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final isMoneyCommand =
        normalized.contains('open money') ||
        normalized.contains('money mode') ||
        normalized.contains('money sense') ||
        (normalized.contains('money') &&
            (normalized.contains('sense') || normalized.contains('cents')));
    final isStreetCommand =
        normalized.contains('open street') ||
        normalized.contains('street mode') ||
        normalized.contains('street smart') ||
        (normalized.contains('street') && normalized.contains('smart'));

    final now = DateTime.now();
    if (isMoneyCommand) {
      if (now.difference(_lastVoiceCommandAt) < _voiceCommandCooldown) {
        return;
      }
      _lastVoiceCommandAt = now;
      if (mounted) {
        await _navigateWithVoicePause('/money-sense');
      }
      return;
    }

    if (isStreetCommand) {
      if (now.difference(_lastVoiceCommandAt) < _voiceCommandCooldown) {
        return;
      }
      _lastVoiceCommandAt = now;
      if (mounted) {
        await _navigateWithVoicePause('/street-smart');
      }
      return;
    }

    if (spoken.contains('help me call') || spoken.contains('help me, call')) {
      if (now.difference(_lastVoiceCommandAt) < _voiceCommandCooldown) {
        return;
      }
      _lastVoiceCommandAt = now;
      await _triggerEmergencyCall();
    }
  }

  Future<void> _triggerEmergencyCall() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('mizhi_emergency_contact')?.trim() ?? '';
    final rawPhone = prefs.getString('mizhi_emergency_phone')?.trim() ?? '';

    if (rawPhone.isEmpty) {
      await _flutterTts.stop();
      await _flutterTts.speak('No emergency contact saved. Please add one.');
      if (mounted) {
        await _navigateWithVoicePause('/emergency-contact');
      }
      return;
    }

    final normalizedPhone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: normalizedPhone);

    await _flutterTts.stop();
    await _flutterTts.speak(
      name.isNotEmpty ? 'Calling $name' : 'Calling emergency contact',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        if (!mounted) return;
        await _navigateWithVoicePause('/emergency-contact');
      }
    } catch (_) {
      if (!mounted) return;
      await _navigateWithVoicePause('/emergency-contact');
    }
  }

  @override
  void dispose() {
    _restartListenTimer?.cancel();
    if (_speech.isListening) {
      _speech.stop();
    }
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
        height: 120,
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
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
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
                        child: const Text(
                          "MIZHI",
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
                        _getGreeting(),
                        style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Help text
                      const Text(
                        "How can I help you today?",
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
                        title: "STREET SMART",
                        subtitle: "Detect obstacles",
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
                        title: "MONEY SENSE",
                        subtitle: "Identify currency",
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
                        title: "EMERGENCY CONTACT",
                        subtitle: "",
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
