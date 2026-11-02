import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

class Detection {
  final String label;
  final double confidence;
  // Coordinates in the upright camera frame, before preview cropping.
  final Rect boundingBox;

  Detection(this.label, this.confidence, this.boundingBox);
}

int cameraImageRotation(
  CameraDescription camera,
  DeviceOrientation orientation,
) {
  final deviceDegrees = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  final adjustment = camera.lensDirection == CameraLensDirection.front
      ? deviceDegrees
      : -deviceDegrees;
  return (camera.sensorOrientation + adjustment + 360) % 360;
}

/// The same resize and padding are used for pixels and decoded boxes.
class DetectionImageTransform {
  final int frameWidth;
  final int frameHeight;
  final int inputWidth;
  final int inputHeight;
  late final int resizedWidth;
  late final int resizedHeight;
  late final int padLeft;
  late final int padTop;

  DetectionImageTransform({
    required this.frameWidth,
    required this.frameHeight,
    required this.inputWidth,
    required this.inputHeight,
  }) {
    if ([frameWidth, frameHeight, inputWidth, inputHeight].any((n) => n <= 0)) {
      throw ArgumentError('Image dimensions must be positive');
    }
    final scale = math.min(inputWidth / frameWidth, inputHeight / frameHeight);
    resizedWidth = (frameWidth * scale).round().clamp(1, inputWidth);
    resizedHeight = (frameHeight * scale).round().clamp(1, inputHeight);
    padLeft = (inputWidth - resizedWidth) ~/ 2;
    padTop = (inputHeight - resizedHeight) ~/ 2;
  }

  Rect fromNormalizedBox(List<double> box) {
    final scaleX = resizedWidth / frameWidth;
    final scaleY = resizedHeight / frameHeight;
    // Ultralytics NMS export: [xmin, ymin, xmax, ymax, score, classId].
    return Rect.fromLTRB(
      ((box[0] * inputWidth - padLeft) / scaleX).clamp(
        0.0,
        frameWidth.toDouble(),
      ),
      ((box[1] * inputHeight - padTop) / scaleY).clamp(
        0.0,
        frameHeight.toDouble(),
      ),
      ((box[2] * inputWidth - padLeft) / scaleX).clamp(
        0.0,
        frameWidth.toDouble(),
      ),
      ((box[3] * inputHeight - padTop) / scaleY).clamp(
        0.0,
        frameHeight.toDouble(),
      ),
    );
  }
}

class DetectionImagePlane {
  final Uint8List bytes;
  final int rowStride;
  final int pixelStride;

  DetectionImagePlane(this.bytes, this.rowStride, this.pixelStride);
}

class DetectionImageInput {
  final int width;
  final int height;
  final int rotationDegrees;
  final ImageFormatGroup format;
  final List<DetectionImagePlane> planes;
  final DetectionImageTransform transform;

  DetectionImageInput({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.format,
    required this.planes,
    required this.transform,
  });

  factory DetectionImageInput.fromCameraImage(
    CameraImage image, {
    required int rotationDegrees,
    required int inputWidth,
    required int inputHeight,
  }) {
    final swapAxes = rotationDegrees == 90 || rotationDegrees == 270;
    return DetectionImageInput(
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
      format: image.format.group,
      planes: image.planes
          .map(
            (p) => DetectionImagePlane(
              p.bytes,
              p.bytesPerRow,
              p.bytesPerPixel ??
                  (image.format.group == ImageFormatGroup.bgra8888 ? 4 : 1),
            ),
          )
          .toList(growable: false),
      transform: DetectionImageTransform(
        frameWidth: swapAxes ? image.height : image.width,
        frameHeight: swapAxes ? image.width : image.height,
        inputWidth: inputWidth,
        inputHeight: inputHeight,
      ),
    );
  }
}

/// RGB floats in [0, 1], rotated upright and letterboxed with gray padding.
Float32List prepareDetectionImage(
  DetectionImageInput input, {
  Float32List? output,
}) {
  if (![0, 90, 180, 270].contains(input.rotationDegrees)) {
    throw ArgumentError('Rotation must be a multiple of 90 degrees');
  }
  if (!((input.format == ImageFormatGroup.yuv420 && input.planes.length == 3) ||
      (input.format == ImageFormatGroup.bgra8888 &&
          input.planes.length == 1))) {
    throw UnsupportedError('Unsupported camera format: ${input.format}');
  }
  final t = input.transform;
  final length = t.inputWidth * t.inputHeight * 3;
  if (output != null && output.length != length) {
    throw ArgumentError(
      'Output buffer does not match the model input dimensions',
    );
  }
  final out = output ?? Float32List(length);
  out.fillRange(0, out.length, 114 / 255);

  for (int y = 0; y < t.resizedHeight; y++) {
    final sy = ((y + 0.5) * t.frameHeight / t.resizedHeight - 0.5).clamp(
      0.0,
      t.frameHeight - 1.0,
    );
    final y0 = sy.floor();
    final y1 = math.min(y0 + 1, t.frameHeight - 1);
    final fy = sy - y0;
    for (int x = 0; x < t.resizedWidth; x++) {
      final sx = ((x + 0.5) * t.frameWidth / t.resizedWidth - 0.5).clamp(
        0.0,
        t.frameWidth - 1.0,
      );
      final x0 = sx.floor();
      final x1 = math.min(x0 + 1, t.frameWidth - 1);
      final fx = sx - x0;
      final a = _rgbAt(input, x0, y0);
      final b = _rgbAt(input, x1, y0);
      final c = _rgbAt(input, x0, y1);
      final d = _rgbAt(input, x1, y1);
      final offset = ((y + t.padTop) * t.inputWidth + x + t.padLeft) * 3;
      for (int channel = 0; channel < 3; channel++) {
        final shift = (2 - channel) * 8;
        final top = ((a >> shift) & 255) * (1 - fx) + ((b >> shift) & 255) * fx;
        final bottom =
            ((c >> shift) & 255) * (1 - fx) + ((d >> shift) & 255) * fx;
        out[offset + channel] = (top * (1 - fy) + bottom * fy) / 255;
      }
    }
  }
  return out;
}

int _rgbAt(DetectionImageInput input, int x, int y) {
  final (sx, sy) = switch (input.rotationDegrees) {
    90 => (y, input.height - 1 - x),
    180 => (input.width - 1 - x, input.height - 1 - y),
    270 => (input.width - 1 - y, x),
    _ => (x, y),
  };
  if (input.format == ImageFormatGroup.bgra8888) {
    final p = input.planes[0];
    final i = sy * p.rowStride + sx * p.pixelStride;
    return (p.bytes[i + 2] << 16) | (p.bytes[i + 1] << 8) | p.bytes[i];
  }
  final yp = input.planes[0];
  final up = input.planes[1];
  final vp = input.planes[2];
  final yv = math.max(
    0,
    yp.bytes[sy * yp.rowStride + sx * yp.pixelStride] - 16,
  );
  final u =
      up.bytes[(sy ~/ 2) * up.rowStride + (sx ~/ 2) * up.pixelStride] - 128;
  final v =
      vp.bytes[(sy ~/ 2) * vp.rowStride + (sx ~/ 2) * vp.pixelStride] - 128;
  final r = ((298 * yv + 409 * v + 128) >> 8).clamp(0, 255);
  final g = ((298 * yv - 100 * u - 208 * v + 128) >> 8).clamp(0, 255);
  final b = ((298 * yv + 516 * u + 128) >> 8).clamp(0, 255);
  return (r << 16) | (g << 8) | b;
}

List<Detection> decodeYoloDetections(
  List<List<double>> output,
  List<String> labels,
  DetectionImageTransform transform, {
  double minimumConfidence = 0.25,
}) {
  final detections = <Detection>[];
  for (final row in output) {
    if (row.length != 6 || row.any((v) => !v.isFinite)) continue;
    final score = row[4];
    if (score < minimumConfidence || score > 1) continue;
    final classId = row[5].round();
    if (classId < 0 ||
        classId >= labels.length ||
        (row[5] - classId).abs() > 0.001) {
      continue;
    }
    final box = transform.fromNormalizedBox(row);
    if (box.width <= 0 || box.height <= 0) continue;
    detections.add(Detection(labels[classId], score, box));
  }
  detections.sort((a, b) => b.confidence.compareTo(a.confidence));
  return detections;
}

/// Matches the centered BoxFit.cover used by the camera preview.
Rect detectionBoxOnPreview(
  Rect box,
  Size frame,
  Size preview, {
  bool mirror = false,
}) {
  final scale = math.max(
    preview.width / frame.width,
    preview.height / frame.height,
  );
  final left = mirror ? frame.width - box.right : box.left;
  return Rect.fromLTWH(
    left * scale + (preview.width - frame.width * scale) / 2,
    box.top * scale + (preview.height - frame.height * scale) / 2,
    box.width * scale,
    box.height * scale,
  );
}
