import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:mizhi/services/detection_pipeline.dart';

/// Admits fresh frames at the speed the device can sustain, without a backlog.
class DetectionCadence {
  static const minimumInterval = Duration(milliseconds: 120);
  static const maximumInterval = Duration(milliseconds: 500);
  static const recoveryTime = Duration(milliseconds: 20);
  final Duration minimum;
  final Duration maximum;
  final Duration recovery;
  Duration interval;
  DetectionCadence({
    this.minimum = minimumInterval,
    this.maximum = maximumInterval,
    this.recovery = recoveryTime,
  }) : interval = minimum;
  DateTime _nextFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _startedAt;
  double? _averageMilliseconds;

  bool tryStart(DateTime now) {
    if (_startedAt != null || now.isBefore(_nextFrame)) return false;
    _startedAt = now;
    return true;
  }

  void finish(Duration elapsed, DateTime now) {
    final start = _startedAt;
    if (start == null) return;
    _startedAt = null;
    final milliseconds = elapsed.inMicroseconds / 1000;
    _averageMilliseconds = _averageMilliseconds == null
        ? milliseconds
        : _averageMilliseconds! * 0.75 + milliseconds * 0.25;
    interval = Duration(
      milliseconds: (_averageMilliseconds! * 1.1).round().clamp(
        minimum.inMilliseconds,
        maximum.inMilliseconds,
      ),
    );
    final scheduled = start.add(interval);
    final recovered = now.add(recovery);
    _nextFrame = scheduled.isAfter(recovered) ? scheduled : recovered;
  }
}

class _DetectionTrack {
  Detection detection;
  DateTime lastSeen;
  int hits = 1;
  _DetectionTrack(this.detection, this.lastSeen);
  bool get confirmed => hits >= 2 || detection.confidence >= 0.55;
}

/// Confirms weaker objects twice and smooths boxes over short detection gaps.
class DetectionTracker {
  static const retention = Duration(milliseconds: 450);
  static const confirmationWindow = Duration(milliseconds: 1200);
  final List<_DetectionTrack> _tracks = [];

  void reset() => _tracks.clear();

  List<Detection> update(List<Detection> detections, DateTime now) {
    _tracks.removeWhere((t) => now.difference(t.lastSeen) > confirmationWindow);
    final unmatched = _tracks.toSet();
    for (final detection in detections) {
      _DetectionTrack? match;
      double bestOverlap = 0.25;
      for (final track in unmatched) {
        if (track.detection.label != detection.label) continue;
        final overlap = _intersectionOverUnion(track.detection, detection);
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          match = track;
        }
      }
      if (match == null) {
        _tracks.add(_DetectionTrack(detection, now));
      } else {
        unmatched.remove(match);
        final a = match.detection.boundingBox;
        final b = detection.boundingBox;
        // Smooth all four edges, including changes in the object's size.
        match.detection = Detection(
          detection.label,
          detection.confidence,
          Rect.lerp(a, b, 0.7)!,
        );
        match.lastSeen = now;
        match.hits++;
      }
    }
    final visible = _tracks
        .where((t) => t.confirmed && now.difference(t.lastSeen) <= retention)
        .map((t) => t.detection)
        .toList();
    visible.sort((a, b) => b.confidence.compareTo(a.confidence));
    return visible;
  }

  double _intersectionOverUnion(Detection a, Detection b) {
    final intersection = a.boundingBox.intersect(b.boundingBox);
    final area =
        math.max(0.0, intersection.width) * math.max(0.0, intersection.height);
    final union =
        a.boundingBox.width * a.boundingBox.height +
        b.boundingBox.width * b.boundingBox.height -
        area;
    return union > 0 ? area / union : 0;
  }
}
