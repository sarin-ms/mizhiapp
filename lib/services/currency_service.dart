import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mizhi/services/currency_pipeline.dart';
import 'package:mizhi/services/currency_worker.dart';
import 'package:mizhi/services/detection_pipeline.dart';

export 'package:mizhi/services/currency_pipeline.dart' show CurrencyResult;

class CurrencyService {
  CurrencyWorker? _worker;
  bool _disposed = false;
  bool get isInit => _worker != null;

  Future<void> init() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/models/currency_labels.txt',
      );
      final labels = raw
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final model = await rootBundle.load(
        'assets/models/mizhi_money_sense.tflite',
      );
      if (_disposed) return;
      final worker = await CurrencyWorker.start(
        model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
        labels,
      );
      if (_disposed) {
        await worker.close();
      } else {
        _worker = worker;
      }
    } catch (e, s) {
      debugPrint('Currency model initialization failed: $e\n$s');
    }
  }

  Future<CurrencyResult?> classify(
    CameraImage image, {
    int rotationDegrees = 0,
  }) async {
    final worker = _worker;
    if (worker == null) return null;
    final input = DetectionImageInput.fromCameraImage(
      image,
      rotationDegrees: rotationDegrees,
      inputWidth: worker.inputWidth,
      inputHeight: worker.inputHeight,
    );
    final result = await worker.classify(input);
    return identical(worker, _worker) ? result : null;
  }

  void reset() => _worker?.reset();

  Future<void> dispose() async {
    _disposed = true;
    final worker = _worker;
    _worker = null;
    await worker?.close();
  }
}
