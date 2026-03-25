import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── frame list — add or remove based on how many images you have ──
  final List<String> _frames = [
    'assets/images/eye_closed.png',
    'assets/images/eye_half.png', // delete this line if you only have 2 images
    'assets/images/eye_open.png',
  ];

  int _currentFrame = 0;
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    _playAnimation();
  }

  Future<bool> _allPermissionsGranted() async {
    final cameraStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    final contactsStatus = await Permission.contacts.status;
    final allGranted =
        cameraStatus.isGranted &&
        micStatus.isGranted &&
        contactsStatus.isGranted;

    return allGranted;
  }

  Future<void> _requestPermissionsIfNeeded() async {
    final allGranted = await _allPermissionsGranted();
    if (!allGranted) {
      await Future.wait([
        Permission.camera.request(),
        Permission.microphone.request(),
        Permission.contacts.request(),
      ]);
    }
  }

  Future<void> _playAnimation() async {
    // Request permissions immediately (silently if already granted)
    await _requestPermissionsIfNeeded();

    // Short pause before starting
    await Future.delayed(const Duration(milliseconds: 400));

    // Play frames forward — eye opening
    for (int i = 0; i < _frames.length; i++) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (mounted) setState(() => _currentFrame = i);
    }

    // Hold open
    await Future.delayed(const Duration(milliseconds: 300));

    // Play frames backward — eye closing
    for (int i = _frames.length - 2; i >= 0; i--) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) setState(() => _currentFrame = i);
    }

    // Hold closed briefly
    await Future.delayed(const Duration(milliseconds: 200));

    // Open again — final reveal
    for (int i = 0; i < _frames.length; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) setState(() => _currentFrame = i);
    }

    // Show text
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() => _showText = true);

    // Auto navigate after 1 second
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      final allPermissionsGranted = await _allPermissionsGranted();
      final route = allPermissionsGranted ? '/home' : '/permissions';
      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),

            // ── Eye animation ──
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 80),
                child: Image.asset(
                  _frames[_currentFrame],
                  key: ValueKey(_currentFrame),
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── App name ──
            AnimatedOpacity(
              opacity: _showText ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: AnimatedSlide(
                offset: _showText ? Offset.zero : const Offset(0, 0.3),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                child: const Column(
                  children: [
                    Text(
                      'MIZHI',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your AI eyes. Always.',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }
}
