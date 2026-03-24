import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

class CurrencyResult {
  final String denomination;
  final double confidence;

  CurrencyResult({required this.denomination, required this.confidence});
}

const Map<String, String> denominationNames = {
  '10': 'Ten Rupees',
  '20': 'Twenty Rupees',
  '50': 'Fifty Rupees',
  '100': 'One Hundred Rupees',
  '200': 'Two Hundred Rupees',
  '500': 'Five Hundred Rupees',
  '2000': 'Two Thousand Rupees',
};

class CurrencyService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInit = false;
  bool get isInit => _isInit;

  final Map<String, DateTime> _lastAlertTime = {};

  static const int inputSize = 224;

  Future<void> init() async {
    try {
      debugPrint('CurrencyService: starting init...');

      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mizhi_money_sense.tflite',
        options: options,
      );
      debugPrint('CurrencyService: model loaded OK');

      final raw = await rootBundle.loadString(
        'assets/models/currency_labels.txt',
      );
      debugPrint('CurrencyService: raw labels = "$raw"');

      _labels = raw
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      debugPrint(
        'CurrencyService: labels loaded: ${_labels.length} → $_labels',
      );

      final inShape = _interpreter!.getInputTensor(0).shape;
      final outShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint('CurrencyService: input=$inShape output=$outShape');

      _isInit = true;
      debugPrint('CurrencyService: init complete!');
    } catch (e, stack) {
      debugPrint('CurrencyService INIT FAILED: $e');
      debugPrint('Stack: $stack');
    }
  }

  // Convert YUV420 CameraImage to Uint8List [1, 224, 224, 3] (raw 0-255 RGB)
  // Model expects uint8 input, NOT float32
  Uint8List _toUint8(CameraImage img) {
    final yBuf = img.planes[0].bytes;
    final uBuf = img.planes[1].bytes;
    final vBuf = img.planes[2].bytes;
    final yRow = img.planes[0].bytesPerRow;
    final uvRow = img.planes[1].bytesPerRow;
    final uvPx = img.planes[1].bytesPerPixel ?? 1;
    final w = img.width;
    final h = img.height;

    final out = Uint8List(inputSize * inputSize * 3);
    int i = 0;

    for (int py = 0; py < inputSize; py++) {
      final sy = py * h ~/ inputSize;
      for (int px = 0; px < inputSize; px++) {
        final sx = px * w ~/ inputSize;

        final yv = yBuf[sy * yRow + sx];
        final uvI = (sy ~/ 2) * uvRow + (sx ~/ 2) * uvPx;
        final u = uBuf[uvI] - 128;
        final v = vBuf[uvI] - 128;

        out[i++] = (yv + 1.402 * v).clamp(0, 255).toInt();       // R
        out[i++] = (yv - 0.34414 * u - 0.71414 * v).clamp(0, 255).toInt(); // G
        out[i++] = (yv + 1.772 * u).clamp(0, 255).toInt();       // B
      }
    }
    return out;
  }

  Future<CurrencyResult?> classify(CameraImage cam) async {
    if (!_isInit || _interpreter == null) return null;

    try {
      final flat = _toUint8(cam);
      final input = flat.reshape([1, inputSize, inputSize, 3]);

      // Detect output tensor type and allocate accordingly
      final outTensor = _interpreter!.getOutputTensor(0);
      final outShape = outTensor.shape; // e.g. [1, 7]
      final numClasses = outShape.last;

      // Allocate output matching tensor type
      dynamic output;
      if (outTensor.type.toString().contains('uint8')) {
        output = List.generate(1, (_) => List.filled(numClasses, 0));
      } else {
        output = List.generate(1, (_) => List.filled(numClasses, 0.0));
      }

      _interpreter!.run(input, output);

      // Normalize output to doubles regardless of type
      List<double> probs;
      if (outTensor.type.toString().contains('uint8')) {
        probs = (output[0] as List<int>).map((e) => e / 255.0).toList();
      } else {
        probs = List<double>.from(output[0]);
      }

      double maxProb = 0;
      int maxIdx = 0;
      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > maxProb) {
          maxProb = probs[i];
          maxIdx = i;
        }
      }

      debugPrint('=== CURRENCY DEBUG ===');
      debugPrint('Probs: ${probs.map((p) => p.toStringAsFixed(3)).toList()}');
      debugPrint(
        'Max: $maxProb @ idx $maxIdx = ${maxIdx < _labels.length ? _labels[maxIdx] : "?"}',
      );
      debugPrint('=====================');

      if (maxIdx < 0 || maxIdx >= _labels.length) return null;
      final label = _labels[maxIdx];

      if (maxProb < 0.80) return null;

      // Cooldown: same denomination not re-announced within 5 seconds
      final now = DateTime.now();
      if (_lastAlertTime.containsKey(label)) {
        if (now.difference(_lastAlertTime[label]!).inSeconds < 5) {
          return null;
        }
      }
      _lastAlertTime[label] = now;

      return CurrencyResult(denomination: label, confidence: maxProb);
    } catch (e) {
      debugPrint('classify() error: $e');
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}
