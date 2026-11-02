import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mizhi/services/app_settings.dart';
import 'package:mizhi/services/detection_pipeline.dart';
import 'package:mizhi/services/detection_tracking.dart';
import 'package:mizhi/services/detection_worker.dart';
import 'package:mizhi/utils/alert_messages.dart';
import 'package:mizhi/utils/localization.dart';

export 'package:mizhi/services/detection_pipeline.dart' show Detection;

class DetectionService {
  DetectionWorker? _worker;
  bool _disposed = false;
  final DetectionTracker _tracker = DetectionTracker();
  int? _lastRotation;
  int? _lastWidth;
  int? _lastHeight;
  String get _language => AppSettings.instance.language;
  bool get isInitialized => _worker != null;

  final Map<String, DateTime> _lastAlertTime = {};

  Future<void> init() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/models/street_labels.txt',
      );
      final labels = raw
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final model = await rootBundle.load(
        'assets/models/mizhi_street_smart.tflite',
      );
      if (_disposed) return;
      final worker = await DetectionWorker.start(
        model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
        labels,
      );
      if (_disposed) {
        await worker.close();
        return;
      }
      _worker = worker;
      debugPrint(
        'Street Smart: background detection ready, '
        'input=${_worker!.inputWidth}x${_worker!.inputHeight}, classes=${labels.length}',
      );
    } catch (e, s) {
      debugPrint('DetectionService init error: $e\n$s');
      await dispose();
    }
  }

  Future<List<Detection>> detect(
    CameraImage image, {
    int rotationDegrees = 0,
  }) async {
    final worker = _worker;
    if (worker == null) throw StateError('Object detection is not initialized');
    final input = DetectionImageInput.fromCameraImage(
      image,
      rotationDegrees: rotationDegrees,
      inputWidth: worker.inputWidth,
      inputHeight: worker.inputHeight,
    );
    final detections = await worker.detect(input);
    if (!identical(_worker, worker)) return [];
    if (_lastRotation != rotationDegrees ||
        _lastWidth != image.width ||
        _lastHeight != image.height) {
      _tracker.reset();
      _lastRotation = rotationDegrees;
      _lastWidth = image.width;
      _lastHeight = image.height;
    }
    return _tracker.update(detections, DateTime.now());
  }

  String? getAlertMessage(
    List<Detection> detections, [
    double camW = 480,
    double camH = 640,
    bool mirror = false,
  ]) {
    final now = DateTime.now();
    Detection? top;
    int best = -1;
    for (final d in detections) {
      // Show lower-confidence detections, but keep spoken alerts conservative.
      if (d.confidence < kMinConfidence) continue;
      final last = _lastAlertTime[d.label];
      if (last != null &&
          now.difference(last).inSeconds < kAlertCooldownSeconds) {
        continue;
      }
      final priority =
          alertPriority[d.label] ?? alertPriority[d.label.toLowerCase()] ?? 0;
      if (priority > best) {
        best = priority;
        top = d;
      }
    }
    if (top == null) return null;
    _lastAlertTime[top.label] = now;

    final directionalMsg = _getDirectionalAlertStr(top, camW, camH, mirror);
    if (directionalMsg != null) return directionalMsg;
    final localized = getLocalizedAlert(top.label, _language);
    if (localized.isNotEmpty) return localized;
    return alertMessages[top.label] ??
        alertMessages[top.label.toLowerCase()] ??
        '${top.label} detected';
  }

  String? _getDirectionalAlertStr(
    Detection d,
    double camW,
    double camH,
    bool mirror,
  ) {
    if (camW <= 0 || camH <= 0) return null;
    final centerX = d.boundingBox.center.dx / camW;
    final fractionX = mirror ? 1 - centerX : centerX;
    final areaRatio =
        d.boundingBox.width * d.boundingBox.height / (camW * camH);
    final isClose = areaRatio > 0.08 || d.boundingBox.height / camH > 0.3;
    if (isClose && fractionX >= 0.3 && fractionX <= 0.7) {
      return directionalAnnouncement(d.label, fractionX <= 0.5, _language);
    }
    return null;
  }

  Future<void> reloadLanguage() async {
    await AppSettings.instance.load();
  }

  Future<void> dispose() async {
    _disposed = true;
    final worker = _worker;
    _worker = null;
    _tracker.reset();
    await worker?.close();
  }
}
