import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mizhi/l10n/app_localizations.dart';
import 'package:mizhi/services/app_settings.dart';
import 'package:mizhi/services/app_voice_service.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:mizhi/services/detection_pipeline.dart'
    show cameraImageRotation;
import 'package:mizhi/services/detection_tracking.dart' show DetectionCadence;
import 'package:mizhi/services/app_audio.dart';
import 'package:mizhi/services/currency_service.dart';
import 'package:mizhi/utils/settings_helper.dart';
import 'package:mizhi/utils/localization.dart';

class MoneySenseScreen extends StatefulWidget {
  const MoneySenseScreen({super.key});

  @override
  State<MoneySenseScreen> createState() => _MoneySenseScreenState();
}

class _MoneySenseScreenState extends State<MoneySenseScreen> {
  bool _modelReady = false;
  bool _cameraActive = false;
  Future<void> _cameraTransition = Future.value();
  String _lastLanguage = AppSettings.instance.language;

  void _settingsChanged() {
    if (_lastLanguage != AppSettings.instance.language) {
      _lastLanguage = AppSettings.instance.language;
      _lastAnnouncedDenomination = '';
    }
    if (mounted) setState(() {});
  }

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isPermissionDenied = false;
  String? _modelError;
  int _cameraGeneration = 0;

  final CurrencyService _currencyService = CurrencyService();
  final AppAudio _flutterTts = AppAudio.instance;

  CurrencyResult? _result;
  String _lastAnnouncedDenomination = "";
  DateTime _lastResultAt = DateTime.fromMillisecondsSinceEpoch(0);
  final _cadence = DetectionCadence(
    minimum: const Duration(milliseconds: 250),
    maximum: const Duration(milliseconds: 1000),
    recovery: const Duration(milliseconds: 50),
  );
  String get _language => AppSettings.instance.language;
  bool _flashlightEnabled = false;
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
    AppSettings.instance.addListener(_settingsChanged);
    AppVoiceService.instance.registerCamera(
      '/money-sense',
      this,
      pause: _pauseCamera,
      resume: _resumeCamera,
      flashlight: _setFlashlight,
    );

    _initServices();
  }

  Future<void> _initServices() async {
    await _currencyService.init();
    if (!mounted) {
      await _currencyService.dispose();
      return;
    }
    if (!_currencyService.isInit) {
      setState(
        () => _modelError =
            'Currency detection could not start. Please reopen Money Sense.',
      );
      return;
    }

    // Step 2: Init TTS with user's saved settings
    await applyTtsSettings(_flutterTts);

    if (!mounted) {
      await _currencyService.dispose();
      return;
    }
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
        if (mounted && _cameraActive && _cadence.tryStart(DateTime.now())) {
          unawaited(_runClassification(image));
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
    final stopwatch = Stopwatch()..start();
    final generation = _cameraGeneration;
    try {
      final camera = _cameraController!;
      final rotation = defaultTargetPlatform == TargetPlatform.iOS
          ? 0
          : cameraImageRotation(
              camera.description,
              camera.value.deviceOrientation,
            );
      final result = await _currencyService.classify(
        image,
        rotationDegrees: rotation,
      );
      if (!mounted || !_cameraActive || generation != _cameraGeneration) return;
      final now = DateTime.now();
      if (result != null) {
        if (_result?.denomination != result.denomination ||
            (_result!.confidence * 100).toInt() !=
                (result.confidence * 100).toInt()) {
          setState(() => _result = result);
        }
        _lastResultAt = now;

        if (result.denomination != _lastAnnouncedDenomination &&
            !AppVoiceService.instance.acceptingCommand &&
            !_flutterTts.speaking) {
          _flutterTts.speak(_currencyAnnouncement(result.denomination));
          _lastAnnouncedDenomination = result.denomination;
        }
      } else {
        if (_result != null &&
            now.difference(_lastResultAt) >= const Duration(seconds: 2)) {
          setState(() => _result = null);
          _lastAnnouncedDenomination = "";
        }
      }
    } catch (e) {
      debugPrint('Currency frame processing failed: $e');
    } finally {
      stopwatch.stop();
      _cadence.finish(stopwatch.elapsed, DateTime.now());
    }
  }

  String _currencyAnnouncement(String denomination) {
    return currencyAnnouncement(denomination, _language);
  }

  Future<void> _resumeCamera() {
    _cameraTransition = _cameraTransition.then((_) async {
      if (!mounted ||
          !_modelReady ||
          _cameraController != null ||
          !AppVoiceService.instance.cameraActive('/money-sense')) {
        return;
      }
      _cameraActive = true;
      await _initCamera();
    });
    return _cameraTransition;
  }

  Future<void> _pauseCamera() {
    _cameraActive = false;
    _cameraGeneration++;
    _currencyService.reset();
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
    AppVoiceService.instance.unregisterCamera('/money-sense', this);
    unawaited(_pauseCamera());
    unawaited(_currencyService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPermissionDenied || _modelError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: _focusedButton == 'back_button'
                  ? const Color(0xFFD4AF37)
                  : Colors.white,
            ),
            onPressed: () => _handleButtonTap(
              'back_button',
              'Go back',
              () => Navigator.pop(context),
            ),
          ),
        ),
        body: Center(
          child: Text(
            context.tr(_modelError ?? "Camera permission required"),
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
            RepaintBoundary(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize?.height ?? 1,
                    height: _cameraController!.value.previewSize?.width ?? 1,
                    child: CameraPreview(_cameraController!),
                  ),
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
              color: const Color(0xFF0A0E21),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: _focusedButton == 'back_button_main'
                          ? const Color(0xFFD4AF37)
                          : Colors.white,
                    ),
                    onPressed: () => _handleButtonTap(
                      'back_button_main',
                      'Go back',
                      _stopAndPop,
                    ),
                  ),
                  Text(
                    context.tr("MONEY SENSE"),
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
                          ? const Color(0xFFD4AF37)
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
                        ? Text(
                            context.tr("Hold note here"),
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
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              decoration: const BoxDecoration(
                color: Color(0xEE0A0E21),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                child: _result == null
                    ? _buildStateA()
                    : _buildStateB(_result!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateA() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.currency_rupee, color: Color(0xFFD4AF37), size: 48),
          const SizedBox(height: 12),
          Text(
            context.tr("Point camera at a currency note"),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 16),
          ),
          const SizedBox(height: 20),
          _buildFlashlightPill(),
        ],
      ),
    );
  }

  Widget _buildStateB(CurrencyResult res) {
    final String fullName = context.tr('{amount} Rupees', {
      'amount': res.denomination,
    });
    final double confPercent = res.confidence * 100;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD4AF37),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                context.tr("CONFIDENCE: "),
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: res.confidence,
                    color: const Color(0xFFD4AF37),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [_buildFlashlightPill()],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () =>
                  _handleButtonTap('announce_again', 'Announce again', () {
                    _flutterTts.speak(_currencyAnnouncement(res.denomination));
                  }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B6914),
                side: _focusedButton == 'announce_again'
                    ? const BorderSide(color: Colors.white, width: 2)
                    : BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volume_up, color: Colors.black),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr("ANNOUNCE AGAIN"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
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

  Widget _buildFlashlightPill() {
    return GestureDetector(
      onTap: () async {
        if (_cameraController != null &&
            _cameraController!.value.isInitialized) {
          await _cameraController!.setFlashMode(
            _flashlightEnabled ? FlashMode.off : FlashMode.torch,
          );
          setState(() => _flashlightEnabled = !_flashlightEnabled);
          await _flutterTts.speak(
            _flashlightEnabled ? 'Flashlight on' : 'Flashlight off',
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _flashlightEnabled
              ? const Color(0xFFFFD700)
              : Colors.grey.shade700,
          borderRadius: BorderRadius.circular(20),
          border: _focusedButton == 'flashlight_toggle'
              ? Border.all(color: Colors.white, width: 2)
              : null,
        ),
        child: Text(
          context.tr(_flashlightEnabled ? 'FLASH: ON' : 'FLASH: OFF'),
          style: TextStyle(
            color: _flashlightEnabled ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4AF37)
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
