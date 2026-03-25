import 'dart:async';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mizhi/services/currency_service.dart';
import 'package:mizhi/utils/settings_helper.dart';
import 'package:mizhi/utils/localization.dart';

class MoneySenseScreen extends StatefulWidget {
  const MoneySenseScreen({super.key});

  @override
  State<MoneySenseScreen> createState() => _MoneySenseScreenState();
}

class _MoneySenseScreenState extends State<MoneySenseScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isPermissionDenied = false;

  final CurrencyService _currencyService = CurrencyService();
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speech = SpeechToText();

  CurrencyResult? _result;
  String _lastAnnouncedDenomination = "";
  int _emptyFrames = 0;
  int _frameCount = 0;
  bool _isProcessing = false;
  String _language = 'English';
  bool _isListening = false;
  bool _speechReady = false;
  Timer? _restartListenTimer;
  static const Duration _restartListeningDelay = Duration(seconds: 2);
  DateTime _lastVoiceCommandAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _voiceCommandCooldown = Duration(seconds: 4);

  String? _focusedButton;

  Future<void> _handleButtonTap(
    String buttonId,
    String spokenText,
    VoidCallback action,
  ) async {
    if (_focusedButton == buttonId) {
      setState(() => _focusedButton = null);
      await _flutterTts.stop();
      action();
    } else {
      setState(() => _focusedButton = buttonId);
      await _flutterTts.stop();
      await _flutterTts.speak(spokenText);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _focusedButton == buttonId) {
          setState(() => _focusedButton = null);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initServices();
    _initSpeech();
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
    if (!mounted || !_speechReady || _isListening) return;
    if (_restartListenTimer?.isActive ?? false) return;

    _restartListenTimer = Timer(_restartListeningDelay, () {
      if (!mounted) return;
      _startListening();
    });
  }

  Future<void> _startListening() async {
    if (!mounted || !_speechReady || _isListening) return;
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

  Future<void> _onSpeechResult(SpeechRecognitionResult result) async {
    final spoken = result.recognizedWords.trim().toLowerCase();
    if (spoken.isEmpty) return;

    final normalized = spoken.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final isStreetCommand =
        normalized.contains('open street') ||
        normalized.contains('street mode') ||
        normalized.contains('street smart') ||
        (normalized.contains('street') && normalized.contains('smart'));
    final isMoneyCommand =
        normalized.contains('open money') ||
        normalized.contains('money mode') ||
        normalized.contains('money sense') ||
        (normalized.contains('money') &&
            (normalized.contains('sense') || normalized.contains('cents')));

    final now = DateTime.now();

    if (isStreetCommand) {
      if (now.difference(_lastVoiceCommandAt) < _voiceCommandCooldown) {
        return;
      }
      _lastVoiceCommandAt = now;
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/street-smart');
      }
      return;
    }

    if (isMoneyCommand) {
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
      if (!launched && mounted) {
        Navigator.pushNamed(context, '/emergency-contact');
      }
    } catch (_) {
      if (mounted) {
        Navigator.pushNamed(context, '/emergency-contact');
      }
    }
  }

  Future<void> _initServices() async {
    // Step 1: Init model FIRST, wait for it completely
    await _currencyService.init();
    debugPrint(
      'Currency service init done. isInit = ${_currencyService.isInit}',
    );

    // Step 2: Init TTS with user's saved settings
    await applyTtsSettings(_flutterTts);
    _language = await currentLanguage();

    // Step 3: Wait for any previous camera to release
    await Future.delayed(const Duration(milliseconds: 800));

    // Step 4: Init camera LAST
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() => _isCameraInitialized = true);

      _cameraController!.startImageStream((CameraImage image) {
        _frameCount++;
        if (_frameCount % 15 == 0 && !_isProcessing) {
          _isProcessing = true;
          _runClassification(image);
        }
      });
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied') {
        if (mounted) setState(() => _isPermissionDenied = true);
      }
      debugPrint('Camera error: $e');
    }
  }

  Future<void> _runClassification(CameraImage image) async {
    final result = await _currencyService.classify(image);

    if (mounted) {
      if (result != null) {
        setState(() {
          _result = result;
        });
        _emptyFrames = 0;

        if (result.denomination != _lastAnnouncedDenomination) {
          _flutterTts.speak(_currencyAnnouncement(result.denomination));
          _lastAnnouncedDenomination = result.denomination;
        }
      } else {
        _emptyFrames++;
        if (_emptyFrames >= 30) {
          setState(() {
            _result = null;
          });
          _lastAnnouncedDenomination = "";
        }
      }
    }

    _isProcessing = false;
  }

  String _currencyAnnouncement(String denomination) {
    return currencyAnnouncement(denomination, _language);
  }

  void _stopAndPop() {
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream();
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _restartListenTimer?.cancel();
    if (_speech.isListening) {
      _speech.stop();
    }
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream();
    }
    _cameraController?.dispose();
    _currencyService.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPermissionDenied) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: _focusedButton == 'back_button'
                  ? const Color(0xFF00D4AA)
                  : Colors.white,
            ),
            onPressed: () => _handleButtonTap(
              'back_button',
              'Go back',
              () => Navigator.pop(context),
            ),
          ),
        ),
        body: const Center(
          child: Text(
            "Camera permission required",
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Layer 1: CameraPreview full screen
          if (_isCameraInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 1,
                  height: _cameraController!.value.previewSize?.width ?? 1,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          // Layer 2: Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 64 + MediaQuery.of(context).padding.top,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
                left: 16,
                right: 16,
              ),
              color: const Color(0x99000000),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: _focusedButton == 'back_button_main'
                          ? const Color(0xFF00D4AA)
                          : Colors.white,
                    ),
                    onPressed: () => _handleButtonTap(
                      'back_button_main',
                      'Go back',
                      _stopAndPop,
                    ),
                  ),
                  const Text(
                    "MONEY SENSE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.settings,
                      color: _focusedButton == 'settings_button'
                          ? const Color(0xFF00D4AA)
                          : Colors.white,
                    ),
                    onPressed: () => _handleButtonTap(
                      'settings_button',
                      'Settings Menu',
                      () {
                        Navigator.pushNamed(context, '/settings');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Layer 3: Viewfinder frame
          if (_isCameraInitialized)
            Center(
              child: SizedBox(
                width: 280,
                height: 180,
                child: CustomPaint(
                  painter: ViewfinderPainter(),
                  child: Center(
                    child: _result == null
                        ? const Text(
                            "Hold note here",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 18,
                            ),
                          )
                        : const SizedBox(),
                  ),
                ),
              ),
            ),

          // Layer 4: Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 220,
              decoration: const BoxDecoration(
                color: Color(0xEE0A0E21),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: _result == null ? _buildStateA() : _buildStateB(_result!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateA() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(
          Icons
              .currency_rupee, // Using default Material Icon since local_atm was fallback, user asked for Icons.currency_rupee
          color: Color(0xFF00D4AA),
          size: 48,
        ),
        SizedBox(height: 12),
        Text(
          "Point camera at a currency note",
          style: TextStyle(color: Colors.white60, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildStateB(CurrencyResult res) {
    final String fullName =
        denominationNames[res.denomination] ?? "${res.denomination} Rupees";
    final double confPercent = res.confidence * 100;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "₹${res.denomination}",
            style: const TextStyle(
              color: Colors.white,
              fontSize:
                  56, // Slightly scaled down from 72sp to avoid overflow vertically, but let's use 72sp if possible
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fullName.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF00D4AA),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "CONFIDENCE: ",
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: res.confidence,
                    color: const Color(0xFF00D4AA),
                    backgroundColor: Colors.white24,
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${confPercent.toInt()}%",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () =>
                  _handleButtonTap('announce_again', 'Announce again', () {
                    _flutterTts.speak(_currencyAnnouncement(res.denomination));
                  }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D4AA),
                side: _focusedButton == 'announce_again'
                    ? const BorderSide(color: Colors.white, width: 2)
                    : BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.volume_up, color: Colors.black),
                  SizedBox(width: 8),
                  Text(
                    "ANNOUNCE AGAIN",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D4AA)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    const double lineLength = 40.0;

    // Top Left
    canvas.drawLine(const Offset(0, 0), const Offset(lineLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, lineLength), paint);

    // Top Right
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - lineLength, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, lineLength),
      paint,
    );

    // Bottom Left
    canvas.drawLine(
      Offset(0, size.height),
      Offset(lineLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - lineLength),
      paint,
    );

    // Bottom Right
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - lineLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - lineLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
