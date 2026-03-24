import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  List<Detection> _currentDetections = [];
  bool _isDetecting = false;
  int _frameCount = 0;

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
        _frameCount++;
        if (_frameCount % 25 == 0 && !_isDetecting) {
          _isDetecting = true;
          _runDetection(image);
        }
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
    try {
      // Run on compute isolate to avoid blocking UI thread
      final detections = await _detectionService.detect(image);

      if (!mounted) return;

      setState(() => _currentDetections = detections);

      final msg = _detectionService.getAlertMessage(detections);
      if (msg != null) {
        if (_voiceEnabled) await _flutterTts.speak(msg);
        if (_vibrationEnabled) {
          if (await Vibration.hasVibrator() == true) {
            Vibration.vibrate(duration: 300);
          }
        }
      }
    } finally {
      _isDetecting = false;
    }
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isOn ? colorOn : Colors.grey.shade700,
          borderRadius: BorderRadius.circular(20),
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
                onPressed: () => Navigator.pop(context),
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
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _previewW,
                  height: _previewH,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          // Layer 2: Bounding boxes scaled to screen
          if (_isCameraInitialized && _currentDetections.isNotEmpty)
            LayoutBuilder(
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
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _stopAndPop,
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
                    icon: const Icon(
                      Icons.stop_circle,
                      color: Colors.red,
                      size: 32,
                    ),
                    onPressed: _stopAndPop,
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
                        color: const Color(0xFF00D4AA).withOpacity(0.2),
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
                        onTap: () =>
                            setState(() => _voiceEnabled = !_voiceEnabled),
                      ),
                      const SizedBox(width: 12),
                      _buildPill(
                        isOn: _vibrationEnabled,
                        labelOn: 'VIBRATION: ON',
                        labelOff: 'VIBRATION: OFF',
                        colorOn: Colors.purple,
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
      final r = Rect.fromLTWH(
        det.boundingBox.left * scaleX,
        det.boundingBox.top * scaleY,
        det.boundingBox.width * scaleX,
        det.boundingBox.height * scaleY,
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
