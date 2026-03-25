import 'dart:async';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import 'package:mizhi/services/detection_service.dart';
import 'package:mizhi/utils/settings_helper.dart';

class StreetSmartScreen extends StatefulWidget {
  const StreetSmartScreen({super.key});

  @override
  State<StreetSmartScreen> createState() => _StreetSmartScreenState();
}

class _StreetSmartScreenState extends State<StreetSmartScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isPermissionDenied = false;

  final DetectionService _detectionService = DetectionService();
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speech = SpeechToText();

  List<Detection> _currentDetections = [];
  bool _isDetecting = false;
  int _frameCount = 0;
  DateTime _nextDetectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _baseDetectionInterval = Duration(milliseconds: 900);
  static const Duration _maxDetectionInterval = Duration(milliseconds: 2200);
  static const int _baseDetectionEveryNFrames = 14;
  int _dynamicDetectionEveryNFrames = _baseDetectionEveryNFrames;
  Duration _dynamicDetectionInterval = _baseDetectionInterval;
  String _lastDetectionSignature = '';
  bool _hasVibrator = false;
  bool _isAlertInProgress = false;
  DateTime _lastAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _alertInterval = Duration(seconds: 4);
  static const Duration _sameAlertSpeakCooldown = Duration(seconds: 7);
  String _lastSpokenAlert = '';
  DateTime _lastSpokenAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
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

  bool _voiceEnabled = true;
  bool _vibrationEnabled = true;

  // Store preview dimensions for correct box scaling
  double _previewW = 1;
  double _previewH = 1;

  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initServices();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          _scheduleListeningRestart();
        }
      },
      onError: (_) {
        if (!mounted) return;
        _isListening = false;
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
      listenFor: const Duration(seconds: 90),
      pauseFor: const Duration(seconds: 12),
      listenOptions: SpeechListenOptions(partialResults: false),
      onResult: _onSpeechResult,
    );
    _isListening = _speech.isListening;
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
        Navigator.pushReplacementNamed(context, '/money-sense');
      }
      return;
    }

    if (isStreetCommand) {
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

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initServices() async {
    await _detectionService.init();

    // Apply user's saved TTS settings (language, speed, volume)
    await applyTtsSettings(_flutterTts);
    _vibrationEnabled = await loadVibrationPref();
    _hasVibrator = await Vibration.hasVibrator();

    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      // Store actual preview size for box scaling
      final previewSize = _cameraController!.value.previewSize!;
      _previewW = previewSize.height; // rotated on Android
      _previewH = previewSize.width;

      setState(() => _isCameraInitialized = true);

      _cameraController!.startImageStream((CameraImage image) {
        if (_isDetecting) return;
        _frameCount++;
        if (_frameCount % _dynamicDetectionEveryNFrames != 0) return;

        final now = DateTime.now();
        if (now.isBefore(_nextDetectionAt)) return;

        _isDetecting = true;
        _nextDetectionAt = now.add(_dynamicDetectionInterval);
        _runDetection(image);
      });
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied') {
        if (mounted) setState(() => _isPermissionDenied = true);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _runDetection(CameraImage image) async {
    final sw = Stopwatch()..start();
    try {
      // Detection is throttled to keep camera preview and UI responsive.
      final detections = await _detectionService.detect(image);
      final visibleDetections = detections.take(3).toList(growable: false);

      if (!mounted) return;

      final signature = _buildDetectionSignature(visibleDetections);
      if (signature != _lastDetectionSignature) {
        setState(() {
          _currentDetections = visibleDetections;
          _lastDetectionSignature = signature;
        });
      }

      final msg = _detectionService.getAlertMessage(
        detections,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final now = DateTime.now();
      if (msg != null &&
          !_isAlertInProgress &&
          _shouldSpeakAlert(msg, now) &&
          now.difference(_lastAlertAt) >= _alertInterval) {
        _isAlertInProgress = true;
        _lastAlertAt = now;
        _lastSpokenAlert = msg;
        _lastSpokenAlertAt = now;

        if (_voiceEnabled) {
          _flutterTts.speak(msg);
        }
        if (_vibrationEnabled && _hasVibrator) {
          Vibration.vibrate(duration: 200);
        }

        Future<void>.delayed(const Duration(milliseconds: 700), () {
          _isAlertInProgress = false;
        });
      }
    } finally {
      sw.stop();
      _tuneDetectionCadence(sw.elapsedMilliseconds);
      _isDetecting = false;
    }
  }

  bool _shouldSpeakAlert(String message, DateTime now) {
    if (_lastSpokenAlert != message) return true;
    return now.difference(_lastSpokenAlertAt) >= _sameAlertSpeakCooldown;
  }

  void _tuneDetectionCadence(int detectMs) {
    if (detectMs >= 320) {
      _dynamicDetectionEveryNFrames = (_dynamicDetectionEveryNFrames + 2).clamp(
        14,
        30,
      );
      final grown =
          _dynamicDetectionInterval + const Duration(milliseconds: 300);
      _dynamicDetectionInterval = grown > _maxDetectionInterval
          ? _maxDetectionInterval
          : grown;
      return;
    }

    if (detectMs >= 220) {
      _dynamicDetectionEveryNFrames = (_dynamicDetectionEveryNFrames + 1).clamp(
        14,
        24,
      );
      final grown =
          _dynamicDetectionInterval + const Duration(milliseconds: 150);
      _dynamicDetectionInterval = grown > _maxDetectionInterval
          ? _maxDetectionInterval
          : grown;
      return;
    }

    if (detectMs <= 140) {
      _dynamicDetectionEveryNFrames = (_dynamicDetectionEveryNFrames - 1).clamp(
        10,
        30,
      );
      final shrunk =
          _dynamicDetectionInterval - const Duration(milliseconds: 120);
      _dynamicDetectionInterval = shrunk < _baseDetectionInterval
          ? _baseDetectionInterval
          : shrunk;
    }
  }

  String _buildDetectionSignature(List<Detection> detections) {
    if (detections.isEmpty) return '';
    final top = detections
        .take(3)
        .map((d) => '${d.label}:${(d.confidence * 100).toInt()}')
        .join('|');
    return '$top#${detections.length}';
  }

  Future<void> _stopAndPop() async {
    try {
      if (_cameraController != null) {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        await _cameraController!.dispose();
        _cameraController = null;
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _restartListenTimer?.cancel();
    if (_speech.isListening) {
      _speech.stop();
    }
    _flutterTts.stop();
    _detectionService.dispose();
    try {
      if (_cameraController != null) {
        if (_cameraController!.value.isStreamingImages) {
          _cameraController!.stopImageStream();
        }
        _cameraController!.dispose();
      }
    } catch (_) {}
    super.dispose();
  }

  Widget _buildPill({
    required bool isOn,
    required String labelOn,
    required String labelOff,
    required Color colorOn,
    required VoidCallback onTap,
    required String buttonId,
    required String spokenText,
  }) {
    return GestureDetector(
      onTap: () => _handleButtonTap(buttonId, spokenText, onTap),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isOn ? colorOn : Colors.grey.shade700,
          borderRadius: BorderRadius.circular(20),
          border: _focusedButton == buttonId
              ? Border.all(color: Colors.white, width: 2)
              : null,
        ),
        child: Text(
          isOn ? labelOn : labelOff,
          style: TextStyle(
            color: isOn && colorOn == const Color(0xFF00D4AA)
                ? Colors.black
                : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPermissionDenied) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Camera permission required',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _handleButtonTap(
                  'go_back',
                  'Go back',
                  () => Navigator.pop(context),
                ),
                style: ElevatedButton.styleFrom(
                  side: _focusedButton == 'go_back'
                      ? const BorderSide(color: Colors.white, width: 2)
                      : BorderSide.none,
                ),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Layer 1: Camera preview
          if (_isCameraInitialized)
            RepaintBoundary(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _previewW,
                    height: _previewH,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            ),

          // Layer 2: Bounding boxes scaled to screen
          if (_isCameraInitialized && _currentDetections.isNotEmpty)
            RepaintBoundary(
              child: LayoutBuilder(
                builder: (ctx, constraints) => CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: BoundingBoxPainter(
                    detections: _currentDetections,
                    camW: _cameraController!.value.previewSize!.width,
                    camH: _cameraController!.value.previewSize!.height,
                    screenW: constraints.maxWidth,
                    screenH: constraints.maxHeight,
                  ),
                ),
              ),
            ),

          // Layer 3: Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 64 + MediaQuery.of(context).padding.top,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
                left: 8,
                right: 8,
              ),
              color: const Color(0x99000000),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: _focusedButton == 'back_button'
                          ? const Color(0xFF00D4AA)
                          : Colors.white,
                    ),
                    onPressed: () =>
                        _handleButtonTap('back_button', 'Go back', _stopAndPop),
                  ),
                  const Text(
                    'STREET SMART',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.stop_circle,
                      color: Colors.red,
                      size: _focusedButton == 'stop_button' ? 36 : 32,
                    ),
                    onPressed: () => _handleButtonTap(
                      'stop_button',
                      'Stop checking',
                      _stopAndPop,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Layer 4: Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                color: Color(0xEE0A0E21),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00D4AA).withValues(alpha: 0.2),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF00D4AA),
                        ),
                        child: const Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _opacityAnimation,
                    child: const Text(
                      'LISTENING...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPill(
                        isOn: _voiceEnabled,
                        labelOn: 'VOICE: ON',
                        labelOff: 'VOICE: OFF',
                        colorOn: const Color(0xFF00D4AA),
                        buttonId: 'voice_toggle_pill',
                        spokenText:
                            'Toggle Voice, currently ${_voiceEnabled ? "On" : "Off"}',
                        onTap: () =>
                            setState(() => _voiceEnabled = !_voiceEnabled),
                      ),
                      const SizedBox(width: 12),
                      _buildPill(
                        isOn: _vibrationEnabled,
                        labelOn: 'VIBRATION: ON',
                        labelOff: 'VIBRATION: OFF',
                        colorOn: Colors.purple,
                        buttonId: 'vibration_toggle_pill',
                        spokenText:
                            'Toggle Vibration, currently ${_vibrationEnabled ? "On" : "Off"}',
                        onTap: () => setState(
                          () => _vibrationEnabled = !_vibrationEnabled,
                        ),
                      ),
                    ],
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

class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final double camW; // raw camera width  (e.g. 480)
  final double camH; // raw camera height (e.g. 640)
  final double screenW;
  final double screenH;

  BoundingBoxPainter({
    required this.detections,
    required this.camW,
    required this.camH,
    required this.screenW,
    required this.screenH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Camera is rotated 90° on Android — swap W/H for scale
    final scaleX = screenW / camH;
    final scaleY = screenH / camW;

    final boxPaint = Paint()
      ..color = const Color(0xFF00D4AA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final bgPaint = Paint()..color = const Color(0xCC000000);

    for (final det in detections) {
      // Landscape X maps to Portrait Y
      // Landscape Y maps to Portrait X
      // For 90-degree CW rotation of the back camera:
      // The box returned by det.boundingBox is:
      // det.boundingBox.left = top of portrait screen (X in landscape)
      // det.boundingBox.top = right of portrait screen (Y in landscape)
      // wait, actually we just need sizes to be transposed:
      final boxWOnScreen = det.boundingBox.height * scaleX;
      final boxHOnScreen = det.boundingBox.width * scaleY;

      // Because left/right might be flipped or transposed simply by multiplying,
      // let's do the standard transpose: left => top * scaleX, top => left * scaleY
      final r = Rect.fromLTWH(
        det.boundingBox.top * scaleX,
        det.boundingBox.left * scaleY,
        boxWOnScreen,
        boxHOnScreen,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(10)),
        boxPaint,
      );

      final label =
          '${det.label.toUpperCase()}  ${(det.confidence * 100).toInt()}%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pillTop = (r.top - tp.height - 10).clamp(0.0, screenH);
      final pillRect = Rect.fromLTWH(
        r.left,
        pillTop,
        tp.width + 16,
        tp.height + 8,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(6)),
        bgPaint,
      );
      tp.paint(canvas, Offset(r.left + 8, pillTop + 4));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter old) =>
      old.detections != detections;
}
