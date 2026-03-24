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
  DateTime _lastVoiceCommandAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _voiceCommandCooldown = Duration(seconds: 4);

  Future<void> _handleButtonTap(
    String buttonId,
    String spokenText,
    VoidCallback action,
  ) async {
    if (_focusedButton == buttonId) {
      setState(() {
        _focusedButton = null;
      });
      await _flutterTts.stop();
      action();
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
          _startListening();
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isListening = false);
        // Retry so voice command remains available even after transient errors.
        Future<void>.delayed(const Duration(seconds: 2), _startListening);
      },
    );

    if (_speechReady) {
      _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!mounted || !_speechReady || _isListening) return;
    await _speech.listen(
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: _onSpeechResult,
    );
    if (mounted) {
      setState(() => _isListening = true);
    }
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
        Navigator.pushNamed(context, '/money-sense');
      }
      return;
    }

    if (isStreetCommand) {
      if (now.difference(_lastVoiceCommandAt) < _voiceCommandCooldown) {
        return;
      }
      _lastVoiceCommandAt = now;
      if (mounted) {
        Navigator.pushNamed(context, '/street-smart');
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
        Navigator.pushNamed(context, '/emergency-contact');
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
        Navigator.pushNamed(context, '/emergency-contact');
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/emergency-contact');
    }
  }

  @override
  void dispose() {
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
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color subtitleColor,
    required VoidCallback onTap,
  }) {
    // Mode card with subtle teal InkWell splash on tap, as requested
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          splashColor: const Color(0xFF00D4AA).withValues(alpha: 0.3),
          highlightColor: const Color(0xFF00D4AA).withValues(alpha: 0.1),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                // Left column
                Icon(icon, color: iconColor, size: 48),
                const SizedBox(width: 24),
                // Right column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: TextStyle(color: subtitleColor, fontSize: 15),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Mizhi",
                      style: TextStyle(
                        color: Color(0xFF00D4AA),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _handleButtonTap(
                          'settings',
                          'Settings Menu',
                          () => Navigator.pushNamed(context, '/settings'),
                        );
                      },
                      child: Icon(
                        Icons.settings,
                        color: _focusedButton == 'settings'
                            ? const Color(0xFF00D4AA)
                            : Colors.white,
                        size: 28,
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
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Help text
                      const Text(
                        "WHAT DO YOU NEED HELP WITH?",
                        style: TextStyle(
                          color: Color(0xFF00D4AA),
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Street Smart
                      _buildModeCard(
                        bgColor: const Color(0xFF0F4F45),
                        borderColor: _focusedButton == 'street_smart'
                            ? Colors.white
                            : const Color(0xFF00D4AA),
                        icon: Icons.directions_walk,
                        iconColor: const Color(0xFF00D4AA),
                        title: "STREET SMART",
                        subtitle: "Detect vehicles & obstacles",
                        subtitleColor: const Color(0xFF00D4AA),
                        onTap: () {
                          _handleButtonTap(
                            'street_smart',
                            'Street Smart mode',
                            () => Navigator.pushNamed(context, '/street-smart'),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Money Sense
                      _buildModeCard(
                        bgColor: const Color(0xFF2A1F5F),
                        borderColor: _focusedButton == 'money_sense'
                            ? Colors.white
                            : const Color(0xFF6C3FBF),
                        icon: Icons.currency_rupee,
                        iconColor: const Color(0xFF9B6FE8),
                        title: "MONEY SENSE",
                        subtitle: "Identify currency notes",
                        subtitleColor: const Color(0xFF9B6FE8),
                        onTap: () {
                          _handleButtonTap(
                            'money_sense',
                            'Money sense mode',
                            () => Navigator.pushNamed(context, '/money-sense'),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Emergency Contact button
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: ElevatedButton(
                          onPressed: () {
                            _handleButtonTap(
                              'emergency_contact',
                              'Emergency contact',
                              () => Navigator.pushNamed(
                                context,
                                '/emergency-contact',
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4444),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            side: _focusedButton == 'emergency_contact'
                                ? const BorderSide(
                                    color: Colors.white,
                                    width: 2,
                                  )
                                : BorderSide.none,
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.phone, color: Colors.white, size: 24),
                              SizedBox(width: 12),
                              Text(
                                "EMERGENCY CONTACT",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
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
