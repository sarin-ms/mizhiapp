import 'package:flutter/foundation.dart';
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



  int _ssdNumDet = 0;
  List<List<List<double>>>? _ssdOutBoxes;
  List<List<double>>? _ssdOutClasses;
  List<List<double>>? _ssdOutScores;
  List<double>? _ssdOutCount;

  List<List<List<double>>>? _yoloOutput;

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

      if (kDebugMode) {
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
      }

      _prepareOutputBuffers();

      _isInit = true;

      // Load user's language setting
      final prefs = await SharedPreferences.getInstance();
      _language = prefs.getString('mizhi_language') ?? 'English';
    } catch (e, s) {
      debugPrint('DetectionService init error: $e\n$s');
    }
  }

  void _prepareOutputBuffers() {
    if (_interpreter == null) return;

    if (_numOutputs >= 4) {
      _ssdNumDet = _interpreter!.getOutputTensor(0).shape[1];
      _ssdOutBoxes = List.generate(
        1,
        (_) => List.generate(_ssdNumDet, (_) => List.filled(4, 0.0)),
      );
      _ssdOutClasses = List.generate(1, (_) => List.filled(_ssdNumDet, 0.0));
      _ssdOutScores = List.generate(1, (_) => List.filled(_ssdNumDet, 0.0));
      _ssdOutCount = List.filled(1, 0.0);
      return;
    }

    final outShape = _interpreter!.getOutputTensor(0).shape;
    _yoloOutput = List.generate(
      outShape[0],
      (_) => List.generate(outShape[1], (_) => List.filled(outShape[2], 0.0)),
    );
  }



  Future<List<Detection>> detect(CameraImage cam) async {
    if (!_isInit || _interpreter == null) return [];
    try {
      final inputData = IsolateImageInput(
        width: cam.width,
        height: cam.height,
        inputSize: _inputSize,
        yBuf: cam.planes[0].bytes,
        uBuf: cam.planes[1].bytes,
        vBuf: cam.planes[2].bytes,
        yRow: cam.planes[0].bytesPerRow,
        uvRow: cam.planes[1].bytesPerRow,
        uvPx: cam.planes[1].bytesPerPixel ?? 1,
      );

      final dynamic input;
      if (_isUint8) {
        final uint8Data = await compute(_isolateToUint8, inputData);
        input = uint8Data.reshape([1, _inputSize, _inputSize, 3]);
      } else {
        final float32Data = await compute(_isolateToFloat32, inputData);
        input = float32Data.reshape([1, _inputSize, _inputSize, 3]);
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
    if (_ssdOutBoxes == null ||
        _ssdOutClasses == null ||
        _ssdOutScores == null ||
        _ssdOutCount == null) {
      _prepareOutputBuffers();
      if (_ssdOutBoxes == null ||
          _ssdOutClasses == null ||
          _ssdOutScores == null ||
          _ssdOutCount == null) {
        return [];
      }
    }

    _interpreter!.runForMultipleInputs(
      [input],
      {
        0: _ssdOutBoxes!,
        1: _ssdOutClasses!,
        2: _ssdOutScores!,
        3: _ssdOutCount!,
      },
    );

    final count = _ssdOutCount![0].toInt().clamp(0, _ssdNumDet);
    final W = cam.width.toDouble();
    final H = cam.height.toDouble();
    final List<Detection> detections = [];

    for (int i = 0; i < count; i++) {
      final score = _ssdOutScores![0][i];
      final classId = _ssdOutClasses![0][i].toInt();
      if (classId < 0 || classId >= _labels.length) continue;

      final label = _labels[classId];

      // Different thresholds for different class types
      final threshold =
          (label == 'person' ||
              label == 'car' ||
              label == 'truck' ||
              label == 'bus')
          ? 0.45
          : 0.55;
      if (score < threshold) continue;

      // [ymin, xmin, ymax, xmax]
      final ymin = _ssdOutBoxes![0][i][0];
      final xmin = _ssdOutBoxes![0][i][1];
      final ymax = _ssdOutBoxes![0][i][2];
      final xmax = _ssdOutBoxes![0][i][3];

      final left = (xmin * W).clamp(0.0, W);
      final top = (ymin * H).clamp(0.0, H);
      final width = ((xmax - xmin) * W).clamp(1.0, W - left);
      final height = ((ymax - ymin) * H).clamp(1.0, H - top);

      detections.add(
        Detection(label, score, Rect.fromLTWH(left, top, width, height)),
      );
    }
    return detections;
  }

  List<Detection> _runYOLO(dynamic input, CameraImage cam) {
    if (_yoloOutput == null) {
      _prepareOutputBuffers();
      if (_yoloOutput == null) return [];
    }

    _interpreter!.run(input, _yoloOutput!);

    final W = cam.width.toDouble();
    final H = cam.height.toDouble();
    final List<Detection> detections = [];

    for (final box in _yoloOutput![0]) {
      if (box.length < 6) continue;
      final score = box[4];
      final classId = box[5].round();
      if (classId < 0 || classId >= _labels.length) continue;

      final label = _labels[classId];

      // Different thresholds for different class types
      final threshold =
          (label == 'person' ||
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

      detections.add(
        Detection(label, score, Rect.fromLTWH(left, top, width, height)),
      );
    }

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    return detections.take(5).toList();
  }

  String? getAlertMessage(List<Detection> detections, [double camW = 480, double camH = 640]) {
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
    if (last != null &&
        now.difference(last).inSeconds < kAlertCooldownSeconds) {
      return null;
    }
    _lastAlertTime[top.label] = now;

    final directionalMsg = _getDirectionalAlertStr(top, camW, camH);
    if (directionalMsg != null) return directionalMsg;

    // Try localized message first, fall back to English
    final localized = getLocalizedAlert(top.label, _language);
    if (localized.isNotEmpty) return localized;
    return alertMessages[top.label] ??
        alertMessages[top.label.toLowerCase()] ??
        '${top.label} detected';
  }

  String? _getDirectionalAlertStr(Detection d, double camW, double camH) {
    // The camera image axes: 'cam.width' (camW) maps to Portrait Y ('left', 'width' of box)
    // 'cam.height' (camH) maps to Portrait X ('top', 'height' of box)
    
    final portraitWidth = camH;
    final portraitHeight = camW;
    
    final boxPortraitX = d.boundingBox.top;
    final boxPortraitWidth = d.boundingBox.height;
    final boxPortraitHeight = d.boundingBox.width;

    final portraitCenterX = boxPortraitX + (boxPortraitWidth / 2);
    final fractionX = portraitCenterX / portraitWidth;
    
    final areaRatio = (boxPortraitWidth * boxPortraitHeight) / (portraitWidth * portraitHeight);
    final isClose = areaRatio > 0.08 || (boxPortraitHeight / portraitHeight) > 0.3;
    
    if (isClose && fractionX >= 0.3 && fractionX <= 0.7) {
      if (fractionX <= 0.5) {
        return "${d.label} ahead, move right";
      } else {
        return "${d.label} ahead, move left";
      }
    }
    
    return null;
  }

  /// Reload language from prefs (call after returning from settings)
  Future<void> reloadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('mizhi_language') ?? 'English';
  }

  void dispose() => _interpreter?.close();
}

class IsolateImageInput {
  final int width;
  final int height;
  final int inputSize;
  final Uint8List yBuf;
  final Uint8List uBuf;
  final Uint8List vBuf;
  final int yRow;
  final int uvRow;
  final int uvPx;

  IsolateImageInput({
    required this.width,
    required this.height,
    required this.inputSize,
    required this.yBuf,
    required this.uBuf,
    required this.vBuf,
    required this.yRow,
    required this.uvRow,
    required this.uvPx,
  });
}

Uint8List _isolateToUint8(IsolateImageInput input) {
  final xMap = Int32List(input.inputSize);
  final yMap = Int32List(input.inputSize);
  for (int px = 0; px < input.inputSize; px++) {
    xMap[px] = px * input.width ~/ input.inputSize;
  }
  for (int py = 0; py < input.inputSize; py++) {
    yMap[py] = py * input.height ~/ input.inputSize;
  }

  final out = Uint8List(input.inputSize * input.inputSize * 3);
  int i = 0;
  for (int py = 0; py < input.inputSize; py++) {
    final sy = yMap[py];
    final yBase = sy * input.yRow;
    final uvBase = (sy >> 1) * input.uvRow;
    for (int px = 0; px < input.inputSize; px++) {
      final sx = xMap[px];
      final yv = input.yBuf[yBase + sx];
      final uvI = uvBase + (sx >> 1) * input.uvPx;
      final u = input.uBuf[uvI] - 128;
      final v = input.vBuf[uvI] - 128;

      final c = yv - 16;
      final y = c < 0 ? 0 : c;
      final r = (298 * y + 409 * v + 128) >> 8;
      final g = (298 * y - 100 * u - 208 * v + 128) >> 8;
      final b = (298 * y + 516 * u + 128) >> 8;

      out[i++] = r.clamp(0, 255);
      out[i++] = g.clamp(0, 255);
      out[i++] = b.clamp(0, 255);
    }
  }
  return out;
}

Float32List _isolateToFloat32(IsolateImageInput input) {
  final xMap = Int32List(input.inputSize);
  final yMap = Int32List(input.inputSize);
  for (int px = 0; px < input.inputSize; px++) {
    xMap[px] = px * input.width ~/ input.inputSize;
  }
  for (int py = 0; py < input.inputSize; py++) {
    yMap[py] = py * input.height ~/ input.inputSize;
  }

  final out = Float32List(input.inputSize * input.inputSize * 3);
  int i = 0;
  for (int py = 0; py < input.inputSize; py++) {
    final sy = yMap[py];
    final yBase = sy * input.yRow;
    final uvBase = (sy >> 1) * input.uvRow;
    for (int px = 0; px < input.inputSize; px++) {
      final sx = xMap[px];
      final yv = input.yBuf[yBase + sx];
      final uvI = uvBase + (sx >> 1) * input.uvPx;
      final u = input.uBuf[uvI] - 128;
      final v = input.vBuf[uvI] - 128;

      final c = yv - 16;
      final y = c < 0 ? 0 : c;
      final r = (298 * y + 409 * v + 128) >> 8;
      final g = (298 * y - 100 * u - 208 * v + 128) >> 8;
      final b = (298 * y + 516 * u + 128) >> 8;

      out[i++] = r.clamp(0, 255) / 255.0;
      out[i++] = g.clamp(0, 255) / 255.0;
      out[i++] = b.clamp(0, 255) / 255.0;
    }
  }
  return out;
}
