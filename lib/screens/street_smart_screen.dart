import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mizhi/l10n/app_localizations.dart';
import 'package:mizhi/l10n/object_names.dart';
import 'package:mizhi/services/app_settings.dart';
import 'package:mizhi/services/app_voice_service.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:camera/camera.dart';
import 'package:mizhi/services/app_audio.dart';
import 'package:vibration/vibration.dart';

import 'package:mizhi/services/detection_service.dart';
import 'package:mizhi/services/detection_pipeline.dart'
    show cameraImageRotation, detectionBoxOnPreview;
import 'package:mizhi/services/detection_tracking.dart' show DetectionCadence;
import 'package:mizhi/utils/settings_helper.dart';

class StreetSmartScreen extends StatefulWidget {
  const StreetSmartScreen({super.key});

  @override
  State<StreetSmartScreen> createState() => _StreetSmartScreenState();
}

class _StreetSmartScreenState extends State<StreetSmartScreen>
    with TickerProviderStateMixin {
  bool _modelReady = false;
  bool _cameraActive = false;
  Future<void> _cameraTransition = Future.value();

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isPermissionDenied = false;
  String? _detectionError;

  final DetectionService _detectionService = DetectionService();
  final AppAudio _flutterTts = AppAudio.instance;

  final _overlay =
      ValueNotifier<({List<Detection> detections, Size frameSize})>((
        detections: const [],
        frameSize: const Size(480, 640),
      ));
  List<Detection> get _currentDetections => _overlay.value.detections;
  Size get _detectionFrameSize => _overlay.value.frameSize;
  final DetectionCadence _detectionCadence = DetectionCadence();
  bool _hasVibrator = false;
  bool _isAlertInProgress = false;
  DateTime _lastAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _alertInterval = Duration(seconds: 4);
  static const Duration _sameAlertSpeakCooldown = Duration(seconds: 7);
  String _lastSpokenAlert = '';
  DateTime _lastSpokenAlertAt = DateTime.fromMillisecondsSinceEpoch(0);

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

  bool get _voiceEnabled => AppSettings.instance.voiceFeedback;
  bool get _vibrationEnabled => AppSettings.instance.vibration;
  bool _flashlightEnabled = false;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_settingsChanged);
    AppVoiceService.instance.registerCamera(
      '/street-smart',
      this,
      pause: _pauseCamera,
      resume: _resumeCamera,
      flashlight: _setFlashlight,
    );

    _initAnimations();
    _initServices();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initServices() async {
    await _detectionService.init();
    if (!mounted) {
      _detectionService.dispose();
      return;
    }
    if (!_detectionService.isInitialized) {
      setState(
        () => _detectionError =
            'Object detection could not start. Please reopen Street Smart.',
      );
      return;
    }

    // Apply user's saved TTS settings (language, speed, volume)
    await applyTtsSettings(_flutterTts);
    _hasVibrator = await Vibration.hasVibrator();

    _modelReady = true;
    await _resumeCamera();
  }

  Future<void> _initCamera() async {
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
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() => _isCameraInitialized = true);

      await _cameraController!.startImageStream((CameraImage image) {
        if (!mounted ||
            !_cameraActive ||
            _detectionError != null ||
            !_detectionCadence.tryStart(DateTime.now())) {
          return;
        }
        unawaited(_runDetection(image));
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
      // The worker handles pixels and inference while native preview continues.
      final rotation = _imageRotation();
      final detections = await _detectionService.detect(
        image,
        rotationDegrees: rotation,
      );
      final swapAxes = rotation == 90 || rotation == 270;
      final frameSize = Size(
        (swapAxes ? image.height : image.width).toDouble(),
        (swapAxes ? image.width : image.height).toDouble(),
      );

      if (!mounted ||
          !_cameraActive ||
          _cameraController == null ||
          rotation != _imageRotation()) {
        return;
      }

      // Boxes can move even when their labels and confidence stay the same.
      _overlay.value = (detections: detections, frameSize: frameSize);

      final now = DateTime.now();
      if (_isAlertInProgress || now.difference(_lastAlertAt) < _alertInterval) {
        return;
      }
      final msg = _detectionService.getAlertMessage(
        detections,
        frameSize.width,
        frameSize.height,
        _cameraController!.description.lensDirection ==
            CameraLensDirection.front,
      );
      if (msg != null && _shouldSpeakAlert(msg, now)) {
        _isAlertInProgress = true;
        _lastAlertAt = now;
        _lastSpokenAlert = msg;
        _lastSpokenAlertAt = now;

        if (_voiceEnabled &&
            !AppVoiceService.instance.acceptingCommand &&
            !_flutterTts.speaking) {
          _flutterTts.speak(msg);
        }
        if (_vibrationEnabled && _hasVibrator) {
          Vibration.vibrate(duration: 200);
        }

        Future<void>.delayed(const Duration(milliseconds: 700), () {
          _isAlertInProgress = false;
        });
      }
    } catch (e, s) {
      debugPrint('Street Smart detection error: $e\n$s');
      if (mounted && _cameraActive) {
        setState(() {
          _overlay.value = (
            detections: const [],
            frameSize: _detectionFrameSize,
          );
          _detectionError =
              'Object detection could not process the camera. Please reopen Street Smart.';
        });
      }
    } finally {
      sw.stop();
      _detectionCadence.finish(sw.elapsed, DateTime.now());
    }
  }

  int _imageRotation() {
    // AVFoundation delivers frames in the current capture orientation.
    if (defaultTargetPlatform == TargetPlatform.iOS) return 0;
    final controller = _cameraController!;
    return cameraImageRotation(
      controller.description,
      controller.value.deviceOrientation,
    );
  }

  bool _shouldSpeakAlert(String message, DateTime now) {
    if (_lastSpokenAlert != message) return true;
    return now.difference(_lastSpokenAlertAt) >= _sameAlertSpeakCooldown;
  }

  Future<void> _resumeCamera() {
    _cameraTransition = _cameraTransition.then((_) async {
      if (!mounted ||
          !_modelReady ||
          _cameraController != null ||
          !AppVoiceService.instance.cameraActive('/street-smart')) {
        return;
      }
      _cameraActive = true;
      _pulseController.repeat(reverse: true);
      await _initCamera();
    });
    return _cameraTransition;
  }

  Future<void> _pauseCamera() {
    _cameraActive = false;
    if (mounted) _pulseController.stop();
    _cameraTransition = _cameraTransition.then((_) async {
      final camera = _cameraController;
      _cameraController = null;
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _flashlightEnabled = false;
        });
      }
      if (camera != null) {
        try {
          if (camera.value.isStreamingImages) await camera.stopImageStream();
        } on CameraException catch (e) {
          debugPrint('Camera stream cleanup: $e');
        } finally {
          try {
            await camera.dispose();
          } on CameraException catch (e) {
            debugPrint('Camera disposal: $e');
          }
        }
      }
    });
    return _cameraTransition;
  }

  Future<bool> _setFlashlight(bool enabled) async {
    final camera = _cameraController;
    if (!_cameraActive || camera == null || !camera.value.isInitialized) {
      return false;
    }
    try {
      await camera.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _flashlightEnabled = enabled);
      return true;
    } on CameraException {
      return false;
    }
  }

  Future<void> _stopAndPop() async {
    await _pauseCamera();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_settingsChanged);
    AppVoiceService.instance.unregisterCamera('/street-smart', this);
    unawaited(_pauseCamera());
    _pulseController.dispose();
    _overlay.dispose();
    unawaited(_detectionService.dispose());
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
            color:
                isOn &&
                    (colorOn == const Color(0xFF8B6914) ||
                        colorOn == const Color(0xFFD4AF37))
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
    if (_isPermissionDenied || _detectionError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              Text(
                context.tr(_detectionError ?? 'Camera permission required'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
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
                child: Text(context.tr('Go back')),
              ),
            ],
          ),
        ),
      );
    }

    final previewSize = _cameraController?.value.previewSize;
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final previewWidth = previewSize == null
        ? 1.0
        : (portrait ? previewSize.height : previewSize.width);
    final previewHeight = previewSize == null
        ? 1.0
        : (portrait ? previewSize.width : previewSize.height);
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
                    width: previewWidth,
                    height: previewHeight,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            ),

          // Only detection overlays rebuild for incoming inference results.
          if (_isCameraInitialized)
            ValueListenableBuilder<
              ({List<Detection> detections, Size frameSize})
            >(
              valueListenable: _overlay,
              builder: (context, frame, _) {
                if (frame.detections.isEmpty) return const SizedBox.shrink();
                return RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) => CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: BoundingBoxPainter(
                        detections: frame.detections,
                        language: AppSettings.instance.language,
                        camW: frame.frameSize.width,
                        camH: frame.frameSize.height,
                        mirror:
                            _cameraController!.description.lensDirection ==
                            CameraLensDirection.front,
                        screenW: constraints.maxWidth,
                        screenH: constraints.maxHeight,
                      ),
                    ),
                  ),
                );
              },
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
              color: const Color(0xFF0A0E21),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: _focusedButton == 'back_button'
                          ? const Color(0xFFD4AF37)
                          : Colors.white,
                    ),
                    onPressed: () =>
                        _handleButtonTap('back_button', 'Go back', _stopAndPop),
                  ),
                  Text(
                    context.tr('STREET SMART'),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xEE0A0E21),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFD4AF37),
                        ),
                        child: const Icon(
                          Icons.remove_red_eye,
                          color: Colors.black,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _opacityAnimation,
                    child:
                        ValueListenableBuilder<
                          ({List<Detection> detections, Size frameSize})
                        >(
                          valueListenable: _overlay,
                          builder: (context, frame, _) => Text(
                            _currentDetections.isEmpty
                                ? context.tr('SCANNING...')
                                : _currentDetections
                                      .map(
                                        (d) => localizedObjectName(
                                          d.label,
                                          AppSettings.instance.language,
                                        ).toUpperCase(),
                                      )
                                      .toSet()
                                      .take(4)
                                      .join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildPill(
                        isOn: _voiceEnabled,
                        labelOn: context.tr('VOICE: ON'),
                        labelOff: context.tr('VOICE: OFF'),
                        colorOn: const Color(0xFF8B6914),
                        buttonId: 'voice_toggle_pill',
                        spokenText: context.tr(
                          'Toggle Voice, currently {state}',
                          {'state': context.tr(_voiceEnabled ? 'On' : 'Off')},
                        ),
                        onTap: () => AppSettings.instance.save(
                          'mizhi_voice_feedback',
                          !_voiceEnabled,
                        ),
                      ),
                      _buildPill(
                        isOn: _vibrationEnabled,
                        labelOn: context.tr('VIBRATION: ON'),
                        labelOff: context.tr('VIBRATION: OFF'),
                        colorOn: Colors.purple,
                        buttonId: 'vibration_toggle_pill',
                        spokenText: context.tr(
                          'Toggle Vibration, currently {state}',
                          {
                            'state': context.tr(
                              _vibrationEnabled ? 'On' : 'Off',
                            ),
                          },
                        ),
                        onTap: () => AppSettings.instance.save(
                          'mizhi_vibration',
                          !_vibrationEnabled,
                        ),
                      ),
                      _buildPill(
                        isOn: _flashlightEnabled,
                        labelOn: context.tr('FLASH: ON'),
                        labelOff: context.tr('FLASH: OFF'),
                        colorOn: const Color(0xFFFFD700),
                        buttonId: 'flashlight_toggle_pill',
                        spokenText: context.tr(
                          'Toggle Flashlight, currently {state}',
                          {
                            'state': context.tr(
                              _flashlightEnabled ? 'On' : 'Off',
                            ),
                          },
                        ),
                        onTap: () async {
                          if (_cameraController != null &&
                              _cameraController!.value.isInitialized) {
                            await _cameraController!.setFlashMode(
                              _flashlightEnabled
                                  ? FlashMode.off
                                  : FlashMode.torch,
                            );
                            setState(
                              () => _flashlightEnabled = !_flashlightEnabled,
                            );
                          }
                        },
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
  final double camW; // upright camera frame width
  final double camH; // upright camera frame height
  final double screenW;
  final double screenH;
  final bool mirror;
  final String language;

  BoundingBoxPainter({
    required this.detections,
    required this.camW,
    required this.camH,
    required this.screenW,
    required this.screenH,
    this.mirror = false,
    this.language = 'English',
  });

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final bgPaint = Paint()..color = const Color(0xCC000000);

    for (final det in detections) {
      final r = detectionBoxOnPreview(
        det.boundingBox,
        Size(camW, camH),
        Size(screenW, screenH),
        mirror: mirror,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(10)),
        boxPaint,
      );

      final label =
          '${localizedObjectName(det.label, language).toUpperCase()}  ${(det.confidence * 100).toInt()}%';
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
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (screenW - 16).clamp(0.0, screenW));

      final pillTop = (r.top - tp.height - 10).clamp(0.0, screenH);
      final pillLeft = r.left.clamp(0.0, screenW - tp.width - 16);
      final pillRect = Rect.fromLTWH(
        pillLeft,
        pillTop,
        tp.width + 16,
        tp.height + 8,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(6)),
        bgPaint,
      );
      tp.paint(canvas, Offset(pillLeft + 8, pillTop + 4));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter old) =>
      old.detections != detections ||
      old.camW != camW ||
      old.camH != camH ||
      old.screenW != screenW ||
      old.screenH != screenH ||
      old.mirror != mirror ||
      old.language != language;
}
