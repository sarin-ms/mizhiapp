import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mizhi/utils/settings_helper.dart';
import 'package:mizhi/utils/localization.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await applyTtsSettings(_flutterTts);
    final lang = await currentLanguage();
    final welcome = welcomeMessages[lang] ?? welcomeMessages['English']!;
    await Future.delayed(const Duration(seconds: 1));
    await _flutterTts.speak(welcome);
  }

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
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          splashColor: const Color(0xFF00D4AA).withOpacity(0.3),
          highlightColor: const Color(0xFF00D4AA).withOpacity(0.1),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                // Left column
                Icon(
                  icon,
                  color: iconColor,
                  size: 48,
                ),
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
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 15,
                        ),
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
                padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0),
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
                        Navigator.pushNamed(context, '/settings');
                      },
                      child: const Icon(
                        Icons.settings,
                        color: Colors.white,
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
                        borderColor: const Color(0xFF00D4AA),
                        icon: Icons.directions_walk,
                        iconColor: const Color(0xFF00D4AA),
                        title: "STREET SMART",
                        subtitle: "Detect vehicles & obstacles",
                        subtitleColor: const Color(0xFF00D4AA),
                        onTap: () {
                          Navigator.pushNamed(context, '/street-smart');
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Money Sense
                      _buildModeCard(
                        bgColor: const Color(0xFF2A1F5F),
                        borderColor: const Color(0xFF6C3FBF),
                        icon: Icons.currency_rupee,
                        iconColor: const Color(0xFF9B6FE8),
                        title: "MONEY SENSE",
                        subtitle: "Identify currency notes",
                        subtitleColor: const Color(0xFF9B6FE8),
                        onTap: () {
                          Navigator.pushNamed(context, '/money-sense');
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Emergency Contact button
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/emergency-contact');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4444),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.phone,
                                color: Colors.white,
                                size: 24,
                              ),
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
