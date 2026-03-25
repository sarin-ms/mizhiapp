import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class FirebaseLocationService {
  static const String keyEnabled = 'mizhi_live_tracking';
  static const String keyTrackId = 'mizhi_track_id';
  static const String keyContact = 'mizhi_emergency_contact';
  static const String keyTrackingPass = 'mizhi_tracking_password';

  final FirebaseDatabase _db = FirebaseDatabase.instance;
  Timer? _timer;
  bool _isEnabled = false;
  String? _trackId;
  String? _password;

  bool get isEnabled => _isEnabled;
  String? get trackId => _trackId;

  String get trackingUrl =>
      _trackId != null ? 'https://mizhi-app.web.app/track/$_trackId' : '';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(keyEnabled) ?? false;
    _trackId = prefs.getString(keyTrackId);
    _password = prefs.getString(keyTrackingPass);

    // Generate a unique tracking ID if first time
    if (_trackId == null) {
      _trackId = const Uuid().v4().substring(0, 8).toUpperCase();
      await prefs.setString(keyTrackId, _trackId!);
    }

    if (_isEnabled && _password != null) startTracking();
  }

  Future<void> setEnabled(bool value, {String? password}) async {
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyEnabled, value);

    if (value && password != null) {
      _password = password;
      await prefs.setString(keyTrackingPass, password);
      startTracking();
    } else {
      stopTracking();
      // Mark as offline in Firebase
      await _db.ref('locations/$_trackId/status').set('offline');
    }
  }

  void startTracking() {
    _timer?.cancel();
    _uploadLocation(); // immediately
    _timer = Timer.periodic(
      const Duration(seconds: 30), // every 30 seconds
      (_) => _uploadLocation(),
    );
    debugPrint('FirebaseLocationService: started, trackId=$_trackId');
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _uploadLocation() async {
    try {
      // Check permission
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever)
        return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final now = DateTime.now();

      // Save to Firebase Realtime Database
      await _db.ref('locations/$_trackId').set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'timestamp': now.millisecondsSinceEpoch,
        'time': '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        'status': 'active',
        'battery': 100, // can integrate battery_plus package later
        'password': _password,
      });

      debugPrint('Location uploaded: ${pos.latitude}, ${pos.longitude}');
    } catch (e) {
      debugPrint('_uploadLocation error: $e');
    }
  }

  // Call this when SOS button is tapped
  Future<void> triggerSOS() async {
    await _uploadLocation(); // get latest location
    await _db.ref('locations/$_trackId/sos').set(true);
    await _db.ref('locations/$_trackId/status').set('SOS');
  }

  void dispose() => _timer?.cancel();
}
