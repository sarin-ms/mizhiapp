import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mizhi/utils/alert_messages.dart';
import 'package:mizhi/utils/localization.dart';

class Detection {
  final String label;
  final double confidence;
  final Rect boundingBox;
  Detection(this.label, this.confidence, this.boundingBox);
}

class DetectionService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInit = false;
  bool _isUint8 = false;
  int _inputSize = 300;
  int _numOutputs = 1;
  String _language = 'English';

  final Map<String, DateTime> _lastAlertTime = {};

  Future<void> init() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mizhi_street_smart.tflite',
        options: options,
      );

      final raw = await rootBundle.loadString(
        'assets/models/street_labels.txt',
      );
      _labels = raw
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final inTensor = _interpreter!.getInputTensor(0);
      _inputSize = inTensor.shape[1];
      _isUint8 = inTensor.type.toString().contains('uint8');
      _numOutputs = _interpreter!.getOutputTensors().length;

      debugPrint('=== MODEL INFO ===');
      debugPrint('Labels: ${_labels.length}');
      debugPrint(
        'Input: ${inTensor.shape} type=${inTensor.type} size=$_inputSize uint8=$_isUint8',
      );
      debugPrint('Output tensors: $_numOutputs');
      for (int i = 0; i < _numOutputs; i++) {
        final t = _interpreter!.getOutputTensor(i);
        debugPrint('  [$i]: shape=${t.shape} type=${t.type}');
      }
      debugPrint('==================');

      _isInit = true;

      // Load user's language setting
      final prefs = await SharedPreferences.getInstance();
      _language = prefs.getString('mizhi_language') ?? 'English';
    } catch (e, s) {
      debugPrint('DetectionService init error: $e\n$s');
    }
  }

  Uint8List _toUint8(CameraImage img) {
    final yBuf = img.planes[0].bytes;
    final uBuf = img.planes[1].bytes;
    final vBuf = img.planes[2].bytes;
    final yRow = img.planes[0].bytesPerRow;
    final uvRow = img.planes[1].bytesPerRow;
    final uvPx = img.planes[1].bytesPerPixel ?? 1;
    final w = img.width;
    final h = img.height;
    final out = Uint8List(_inputSize * _inputSize * 3);
    int i = 0;
    for (int py = 0; py < _inputSize; py++) {
      final sy = py * h ~/ _inputSize;
      for (int px = 0; px < _inputSize; px++) {
        final sx = px * w ~/ _inputSize;
        final yv = yBuf[sy * yRow + sx];
        final uvI = (sy ~/ 2) * uvRow + (sx ~/ 2) * uvPx;
        final u = uBuf[uvI] - 128;
        final v = vBuf[uvI] - 128;
        out[i++] = (yv + 1.402 * v).clamp(0, 255).toInt();
        out[i++] = (yv - 0.34414 * u - 0.71414 * v).clamp(0, 255).toInt();
        out[i++] = (yv + 1.772 * u).clamp(0, 255).toInt();
      }
    }
    return out;
  }

  Float32List _toFloat32(CameraImage img) {
    final yBuf = img.planes[0].bytes;
    final uBuf = img.planes[1].bytes;
    final vBuf = img.planes[2].bytes;
    final yRow = img.planes[0].bytesPerRow;
    final uvRow = img.planes[1].bytesPerRow;
    final uvPx = img.planes[1].bytesPerPixel ?? 1;
    final w = img.width;
    final h = img.height;
    final out = Float32List(_inputSize * _inputSize * 3);
    int i = 0;
    for (int py = 0; py < _inputSize; py++) {
      final sy = py * h ~/ _inputSize;
      for (int px = 0; px < _inputSize; px++) {
        final sx = px * w ~/ _inputSize;
        final yv = yBuf[sy * yRow + sx];
        final uvI = (sy ~/ 2) * uvRow + (sx ~/ 2) * uvPx;
        final u = uBuf[uvI] - 128;
        final v = vBuf[uvI] - 128;
        out[i++] = (yv + 1.402 * v).clamp(0, 255) / 255.0;
        out[i++] = (yv - 0.34414 * u - 0.71414 * v).clamp(0, 255) / 255.0;
        out[i++] = (yv + 1.772 * u).clamp(0, 255) / 255.0;
      }
    }
    return out;
  }

  Future<List<Detection>> detect(CameraImage cam) async {
    if (!_isInit || _interpreter == null) return [];
    try {
      final dynamic input;
      if (_isUint8) {
        input = _toUint8(cam).reshape([1, _inputSize, _inputSize, 3]);
      } else {
        input = _toFloat32(cam).reshape([1, _inputSize, _inputSize, 3]);
      }

      if (_numOutputs >= 4) {
        return _runSSD(input, cam);
      } else {
        return _runYOLO(input, cam);
      }
    } catch (e) {
      debugPrint('detect() error: $e');
      return [];
    }
  }

  List<Detection> _runSSD(dynamic input, CameraImage cam) {
    // SSD outputs: boxes[1,N,4], classes[1,N], scores[1,N], count[1]
    final numDet = _interpreter!.getOutputTensor(0).shape[1];

    final outBoxes = List.generate(
      1,
      (_) => List.generate(numDet, (_) => List.filled(4, 0.0)),
    );
    final outClasses = List.generate(1, (_) => List.filled(numDet, 0.0));
    final outScores = List.generate(1, (_) => List.filled(numDet, 0.0));
    final outCount = List.filled(1, 0.0);

    _interpreter!.runForMultipleInputs(
      [input],
      {0: outBoxes, 1: outClasses, 2: outScores, 3: outCount},
    );

    final count = outCount[0].toInt().clamp(0, numDet);
    final W = cam.width.toDouble();
    final H = cam.height.toDouble();
    final List<Detection> detections = [];

    for (int i = 0; i < count; i++) {
      final score = outScores[0][i];
      final classId = outClasses[0][i].toInt();
      if (classId < 0 || classId >= _labels.length) continue;

      final label = _labels[classId];

      // Different thresholds for different class types
      final threshold = (label == 'person' ||
              label == 'car' ||
              label == 'truck' ||
              label == 'bus')
          ? 0.45
          : 0.55;
      if (score < threshold) continue;

      // [ymin, xmin, ymax, xmax]
      final ymin = outBoxes[0][i][0];
      final xmin = outBoxes[0][i][1];
      final ymax = outBoxes[0][i][2];
      final xmax = outBoxes[0][i][3];

      final left = (xmin * W).clamp(0.0, W);
      final top = (ymin * H).clamp(0.0, H);
      final width = ((xmax - xmin) * W).clamp(1.0, W - left);
      final height = ((ymax - ymin) * H).clamp(1.0, H - top);

      debugPrint('SSD: $label ${(score * 100).toInt()}%');
      detections.add(
        Detection(label, score, Rect.fromLTWH(left, top, width, height)),
      );
    }
    return detections;
  }

  List<Detection> _runYOLO(dynamic input, CameraImage cam) {
    final outShape = _interpreter!.getOutputTensor(0).shape;
    final output = List.generate(
      outShape[0],
      (_) => List.generate(outShape[1], (_) => List.filled(outShape[2], 0.0)),
    );
    _interpreter!.run(input, output);

    final W = cam.width.toDouble();
    final H = cam.height.toDouble();
    final List<Detection> detections = [];

    for (final box in output[0]) {
      if (box.length < 6) continue;
      final score = box[4];
      final classId = box[5].round();
      if (classId < 0 || classId >= _labels.length) continue;

      final label = _labels[classId];

      // Different thresholds for different class types
      final threshold = (label == 'person' ||
              label == 'car' ||
              label == 'truck' ||
              label == 'bus')
          ? 0.45
          : 0.55;
      if (score < threshold) continue;

      final left = (box[1] * W).clamp(0.0, W);
      final top = (box[0] * H).clamp(0.0, H);
      final width = ((box[3] - box[1]) * W).clamp(1.0, W - left);
      final height = ((box[2] - box[0]) * H).clamp(1.0, H - top);

      final area = width * height;
      final frameArea = W * H;
      if (area < frameArea * 0.01) continue; // must be >1% of frame

      debugPrint(
        'YOLO: $label ${(score * 100).toInt()}%  area=${(area / frameArea * 100).toInt()}%',
      );
      detections.add(
        Detection(
          label,
          score,
          Rect.fromLTWH(left, top, width, height),
        ),
      );
    }

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    return detections.take(5).toList();
  }

  String? getAlertMessage(List<Detection> detections) {
    if (detections.isEmpty) return null;
    Detection? top;
    int best = -1;
    for (final d in detections) {
      final p =
          alertPriority[d.label] ?? alertPriority[d.label.toLowerCase()] ?? 0;
      if (p > best) {
        best = p;
        top = d;
      }
    }
    if (top == null) return null;
    final now = DateTime.now();
    final last = _lastAlertTime[top.label];
    if (last != null && now.difference(last).inSeconds < kAlertCooldownSeconds)
      return null;
    _lastAlertTime[top.label] = now;

    // Try localized message first, fall back to English
    final localized = getLocalizedAlert(top.label, _language);
    if (localized.isNotEmpty) return localized;
    return alertMessages[top.label] ??
        alertMessages[top.label.toLowerCase()] ??
        '${top.label} detected';
  }

  /// Reload language from prefs (call after returning from settings)
  Future<void> reloadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('mizhi_language') ?? 'English';
  }

  void dispose() => _interpreter?.close();
}
