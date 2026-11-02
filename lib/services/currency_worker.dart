import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:mizhi/services/currency_pipeline.dart';
import 'package:mizhi/services/detection_pipeline.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Persistent worker with reusable tensors and at most one admitted frame.
class CurrencyWorker {
  final _messages = ReceivePort();
  final _ready = Completer<void>(), _exited = Completer<void>();
  late final StreamSubscription<dynamic> _subscription;
  Isolate? _isolate;
  SendPort? _commands;
  Completer<CurrencyResult?>? _pending;
  bool _disposed = false;
  Future<void>? _closing;
  int inputWidth = 0, inputHeight = 0;
  CurrencyWorker._() {
    _subscription = _messages.listen(_onMessage);
  }
  static Future<CurrencyWorker> start(
    Uint8List model,
    List<String> labels,
  ) async {
    final worker = CurrencyWorker._();
    try {
      worker._isolate = await Isolate.spawn(
        _runCurrencyWorker,
        _Configuration(
          worker._messages.sendPort,
          TransferableTypedData.fromList([model]),
          labels,
        ),
        onError: worker._messages.sendPort,
        onExit: worker._messages.sendPort,
        debugName: 'MizhiCurrencyDetection',
      );
      await worker._ready.future.timeout(const Duration(seconds: 20));
      return worker;
    } catch (_) {
      await worker.close();
      rethrow;
    }
  }

  Future<CurrencyResult?> classify(DetectionImageInput input) {
    if (_disposed || _commands == null || _exited.isCompleted) {
      return Future.error(StateError('Currency worker is closed'));
    }
    if (_pending != null) {
      return Future.error(StateError('A currency frame is already processing'));
    }
    final pending = _pending = Completer<CurrencyResult?>();
    _commands!.send(input);
    return pending.future;
  }

  void reset() => _commands?.send('reset');
  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _commands = message;
    } else if (message is _Ready) {
      inputWidth = message.width;
      inputHeight = message.height;
      if (!_ready.isCompleted) _ready.complete();
    } else if (message is _Result) {
      _pending?.complete(message.value);
      _pending = null;
    } else if (message is _Failure || message is List || message == null) {
      if (message == null && !_exited.isCompleted) _exited.complete();
      final error = StateError(
        message is _Failure
            ? message.message
            : 'Currency worker exited: $message',
      );
      if (!_ready.isCompleted) _ready.completeError(error);
      _pending?.completeError(error);
      _pending = null;
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _disposed = true;
    _commands?.send(null);
    if (_isolate != null && !_exited.isCompleted) {
      try {
        await _exited.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        _isolate?.kill(priority: Isolate.immediate);
      }
    }
    _pending?.completeError(StateError('Currency worker is closed'));
    _pending = null;
    await _subscription.cancel();
    _messages.close();
  }
}

class _Configuration {
  final SendPort reply;
  final TransferableTypedData model;
  final List<String> labels;
  _Configuration(this.reply, this.model, this.labels);
}

class _Ready {
  final int width, height;
  _Ready(this.width, this.height);
}

class _Result {
  final CurrencyResult? value;
  _Result(this.value);
}

class _Failure {
  final String message;
  _Failure(this.message);
}

Future<void> _runCurrencyWorker(_Configuration config) async {
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
    final output = interpreter.getOutputTensor(0);
    final shape = input.shape;
    if (input.type != TensorType.uint8 ||
        shape.length != 4 ||
        shape[0] != 1 ||
        shape[3] != 3 ||
        output.shape.length != 2 ||
        output.shape[0] != 1 ||
        output.shape[1] != config.labels.length ||
        ![
          TensorType.uint8,
          TensorType.int8,
          TensorType.float32,
        ].contains(output.type)) {
      throw StateError('Unsupported currency model or labels');
    }
    final height = shape[1], width = shape[2];
    final pixels = Uint8List(width * height * 3);
    final params = output.params;
    final quantized = output.type != TensorType.float32;
    final signed = output.type == TensorType.int8;
    final tracker = CurrencyTracker();
    input.data = pixels;
    interpreter.invoke();
    config.reply.send(_Ready(width, height));
    await for (final message in commands) {
      if (message == null) break;
      if (message == 'reset') {
        tracker.reset();
        continue;
      }
      if (message is! DetectionImageInput) continue;
      try {
        prepareCurrencyImage(message, pixels);
        input.data = pixels;
        interpreter.invoke();
        final probabilities = decodeCurrencyProbabilities(
          output.data,
          quantized: quantized,
          signed: signed,
          scale: params.scale,
          zeroPoint: params.zeroPoint,
        );
        config.reply.send(
          _Result(tracker.update(probabilities, config.labels)),
        );
      } catch (e, s) {
        tracker.reset();
        config.reply.send(_Failure('$e\n$s'));
      }
    }
  } catch (e, s) {
    config.reply.send(_Failure('$e\n$s'));
  } finally {
    interpreter?.close();
    commands.close();
  }
}
