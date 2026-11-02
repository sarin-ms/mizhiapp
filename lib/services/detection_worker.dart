import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:mizhi/services/detection_pipeline.dart';

/// Owns the model in a persistent isolate. Only one frame can be in flight.
class DetectionWorker {
  final ReceivePort _messages = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _exited = Completer<void>();
  late final StreamSubscription<dynamic> _subscription;
  Isolate? _isolate;
  SendPort? _commands;
  Completer<List<Detection>>? _pending;
  bool _disposed = false;
  Future<void>? _closing;
  int inputWidth = 0;
  int inputHeight = 0;

  DetectionWorker._() {
    _subscription = _messages.listen(_onMessage);
  }

  static Future<DetectionWorker> start(
    Uint8List model,
    List<String> labels,
  ) async {
    final worker = DetectionWorker._();
    try {
      worker._isolate = await Isolate.spawn(
        _runDetectionWorker,
        _WorkerConfiguration(
          worker._messages.sendPort,
          TransferableTypedData.fromList([model]),
          labels,
        ),
        onError: worker._messages.sendPort,
        onExit: worker._messages.sendPort,
        debugName: 'MizhiObjectDetection',
      );
      await worker._ready.future.timeout(const Duration(seconds: 20));
      return worker;
    } catch (_) {
      await worker.close();
      rethrow;
    }
  }

  Future<List<Detection>> detect(DetectionImageInput input) {
    if (_disposed || _commands == null || _exited.isCompleted) {
      return Future.error(StateError('Detection worker is closed'));
    }
    if (_pending != null) {
      return Future.error(
        StateError('A detection frame is already processing'),
      );
    }
    final pending = Completer<List<Detection>>();
    _pending = pending;
    _commands!.send(input);
    return pending.future;
  }

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _commands = message;
    } else if (message is _WorkerReady) {
      inputWidth = message.width;
      inputHeight = message.height;
      if (!_ready.isCompleted) _ready.complete();
    } else if (message is List<Detection>) {
      _pending?.complete(message);
      _pending = null;
    } else if (message is _WorkerFailure || message is List) {
      final error = StateError(
        message is _WorkerFailure ? message.message : message.toString(),
      );
      if (!_ready.isCompleted) _ready.completeError(error);
      _pending?.completeError(error);
      _pending = null;
    } else if (message == null) {
      if (!_exited.isCompleted) _exited.complete();
      final error = StateError('Detection worker exited');
      if (!_ready.isCompleted) _ready.completeError(error);
      _pending?.completeError(error);
      _pending = null;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _disposed = true;
    // Let an in-flight native invocation finish before freeing the model.
    _commands?.send(null);
    if (_isolate != null && !_exited.isCompleted) {
      try {
        await _exited.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        _isolate?.kill(priority: Isolate.immediate);
      }
    }
    _pending?.completeError(StateError('Detection worker is closed'));
    _pending = null;
    await _subscription.cancel();
    _messages.close();
  }
}

class _WorkerConfiguration {
  final SendPort reply;
  final TransferableTypedData model;
  final List<String> labels;
  _WorkerConfiguration(this.reply, this.model, this.labels);
}

class _WorkerReady {
  final int width;
  final int height;
  _WorkerReady(this.width, this.height);
}

class _WorkerFailure {
  final String message;
  _WorkerFailure(this.message);
}

Future<void> _runDetectionWorker(_WorkerConfiguration config) async {
  final commands = ReceivePort();
  config.reply.send(commands.sendPort);
  Interpreter? interpreter;
  try {
    final options = InterpreterOptions()..threads = 2;
    try {
      interpreter = Interpreter.fromBuffer(
        config.model.materialize().asUint8List(),
        options: options,
      );
    } finally {
      options.delete();
    }
    final input = interpreter.getInputTensor(0);
    final outputs = interpreter.getOutputTensors();
    if (input.type != TensorType.float32 ||
        input.shape.length != 4 ||
        input.shape[0] != 1 ||
        input.shape[3] != 3 ||
        config.labels.length != 80 ||
        outputs.length != 1 ||
        outputs[0].type != TensorType.float32 ||
        outputs[0].shape.length != 3 ||
        outputs[0].shape[0] != 1 ||
        outputs[0].shape[2] != 6) {
      throw StateError('Unsupported Street Smart model or labels');
    }
    final height = input.shape[1];
    final width = input.shape[2];
    final pixels = Float32List(width * height * 3);
    final pixelBytes = pixels.buffer.asUint8List();
    pixels.fillRange(0, pixels.length, 114 / 255);
    input.data = pixelBytes;
    interpreter.invoke(); // Warm up allocations before streaming.
    config.reply.send(_WorkerReady(width, height));

    await for (final message in commands) {
      if (message == null) break;
      if (message is! DetectionImageInput) continue;
      try {
        prepareDetectionImage(message, output: pixels);
        input.data = pixelBytes;
        interpreter.invoke();
        final bytes = outputs[0].data;
        final flat = Float32List.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes ~/ Float32List.bytesPerElement,
        );
        final rows = List.generate(
          flat.length ~/ 6,
          (i) => Float32List.sublistView(flat, i * 6, i * 6 + 6),
          growable: false,
        );
        config.reply.send(
          decodeYoloDetections(rows, config.labels, message.transform),
        );
      } catch (e, s) {
        config.reply.send(_WorkerFailure('$e\n$s'));
      }
    }
  } catch (e, s) {
    config.reply.send(_WorkerFailure('$e\n$s'));
  } finally {
    interpreter?.close();
    commands.close();
  }
}
