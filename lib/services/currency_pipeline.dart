import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:mizhi/services/detection_pipeline.dart';

class CurrencyResult {
  final String denomination;
  final double confidence;
  const CurrencyResult({required this.denomination, required this.confidence});
}

/// Raw RGB bytes, preserving the currency model's resize and YUV conversion.
/// The worker supplies the same buffer for every frame.
Uint8List prepareCurrencyImage(DetectionImageInput input, Uint8List output) {
  final t = input.transform;
  if (output.length != t.inputWidth * t.inputHeight * 3 ||
      ![0, 90, 180, 270].contains(input.rotationDegrees)) {
    throw ArgumentError('Invalid currency input dimensions or rotation');
  }
  final bgra = input.format == ImageFormatGroup.bgra8888;
  if (!((bgra && input.planes.length == 1) ||
      (input.format == ImageFormatGroup.yuv420 && input.planes.length == 3))) {
    throw UnsupportedError('Unsupported camera format: ${input.format}');
  }
  var offset = 0;
  for (var y = 0; y < t.inputHeight; y++) {
    final uy = y * t.frameHeight ~/ t.inputHeight;
    for (var x = 0; x < t.inputWidth; x++) {
      final ux = x * t.frameWidth ~/ t.inputWidth;
      final (sx, sy) = switch (input.rotationDegrees) {
        90 => (uy, input.height - 1 - ux),
        180 => (input.width - 1 - ux, input.height - 1 - uy),
        270 => (input.width - 1 - uy, ux),
        _ => (ux, uy),
      };
      final p = input.planes[0];
      if (bgra) {
        final i = sy * p.rowStride + sx * p.pixelStride;
        output[offset++] = p.bytes[i + 2];
        output[offset++] = p.bytes[i + 1];
        output[offset++] = p.bytes[i];
      } else {
        final uPlane = input.planes[1], vPlane = input.planes[2];
        final yv = p.bytes[sy * p.rowStride + sx * p.pixelStride];
        final u =
            uPlane.bytes[(sy ~/ 2) * uPlane.rowStride +
                (sx ~/ 2) * uPlane.pixelStride] -
            128;
        final v =
            vPlane.bytes[(sy ~/ 2) * vPlane.rowStride +
                (sx ~/ 2) * vPlane.pixelStride] -
            128;
        output[offset++] = (yv + 1.402 * v).clamp(0, 255).toInt();
        output[offset++] = (yv - 0.34414 * u - 0.71414 * v)
            .clamp(0, 255)
            .toInt();
        output[offset++] = (yv + 1.772 * u).clamp(0, 255).toInt();
      }
    }
  }
  return output;
}

/// Require a strong winner on three consecutive processed frames.
class CurrencyTracker {
  String? _candidate;
  int _frames = 0;
  void reset() {
    _candidate = null;
    _frames = 0;
  }

  CurrencyResult? update(List<double> probabilities, List<String> labels) {
    if (probabilities.length != labels.length ||
        labels.length < 2 ||
        probabilities.any((p) => !p.isFinite || p < 0 || p > 1)) {
      reset();
      return null;
    }
    var best = -1;
    var top = 0.0, second = 0.0;
    for (var i = 0; i < probabilities.length; i++) {
      final value = probabilities[i];
      if (value > top) {
        second = top;
        top = value;
        best = i;
      } else if (value > second) {
        second = value;
      }
    }
    if (best < 0 || top < 0.85 || top - second < 0.18) {
      reset();
      return null;
    }
    final label = labels[best];
    _frames = _candidate == label ? _frames + 1 : 1;
    _candidate = label;
    if (_frames < 3) return null;
    return CurrencyResult(denomination: label, confidence: top);
  }
}

List<double> decodeCurrencyProbabilities(
  Uint8List bytes, {
  required bool quantized,
  required bool signed,
  required double scale,
  required int zeroPoint,
}) {
  if (!quantized) {
    return Float32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ Float32List.bytesPerElement,
    );
  }
  if (scale <= 0 || !scale.isFinite) {
    throw ArgumentError('Invalid output quantization scale');
  }
  return List.generate(bytes.length, (i) {
    final value = signed && bytes[i] > 127 ? bytes[i] - 256 : bytes[i];
    return (value - zeroPoint) * scale;
  }, growable: false);
}
