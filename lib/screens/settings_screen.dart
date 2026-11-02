import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mizhi/l10n/language_catalog.dart' show nativeLanguageNames;
import 'package:mizhi/l10n/app_localizations.dart';
import 'package:mizhi/services/app_settings.dart';
import 'package:mizhi/services/app_voice_service.dart';
import 'package:mizhi/services/app_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mizhi/utils/alert_messages.dart';
import 'package:flutter/services.dart';
import 'package:mizhi/services/firebase_location_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _liveTracking = false;
  final FirebaseLocationService _firebaseService = FirebaseLocationService();

  String _language = 'English';
  String _alertSpeed = 'Normal';
  double _volume = 0.8;
  bool _vibration = true;
  int _cooldownSeconds = 3;
  String _emergencyContact = '';

  final AppAudio _tts = AppAudio.instance;
  String? _focusedButton;

  Future<void> _handleButtonTap(
    String buttonId,
    String spokenText,
    VoidCallback action,
  ) async {
    if (_focusedButton == buttonId) {
      setState(() => _focusedButton = null);
      await _tts.stop();
      action();
    } else {
      setState(() => _focusedButton = buttonId);
      await _tts.stop();
      await _tts.speak(spokenText);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _focusedButton == buttonId) {
          setState(() => _focusedButton = null);
        }
      });
    }
  }

  static const _teal = Color(0xFF00D4AA);
  static const _cardColor = Color(0xFF1A1E35);
  static const _pillUnselected = Color(0xFF2A2E45);

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_settingsChanged);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    await _firebaseService.init();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _liveTracking = _firebaseService.isEnabled;
      _language = AppSettings.instance.language;
      _alertSpeed = AppSettings.instance.alertSpeed;
      _volume = AppSettings.instance.volume;
      _vibration = AppSettings.instance.vibration;
      _cooldownSeconds = AppSettings.instance.cooldown;
      _emergencyContact = prefs.getString('mizhi_emergency_contact') ?? '';
    });
    kAlertCooldownSeconds = _cooldownSeconds;
    _applyTts();
  }

  Future<void> _save(String key, dynamic value) async {
    await AppSettings.instance.save(key, value as Object);
  }

  void _applyTts() {
    unawaited(_tts.configure());
  }

  void _settingsChanged() {
    if (!mounted) return;
    setState(() {
      _language = AppSettings.instance.language;
      _alertSpeed = AppSettings.instance.alertSpeed;
      _volume = AppSettings.instance.volume;
      _vibration = AppSettings.instance.vibration;
      _cooldownSeconds = AppSettings.instance.cooldown;
    });
  }

  // ───────────── reusable row card ─────────────
  Widget _buildSettingRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required Widget trailing,
    VoidCallback? onTap,
    String? buttonId,
    String? spokenText,
  }) {
    return GestureDetector(
      onTap: () {
        if (buttonId != null && spokenText != null && onTap != null) {
          _handleButtonTap(buttonId, spokenText, onTap);
        } else if (onTap != null) {
          onTap();
        } else if (buttonId != null && spokenText != null) {
          _handleButtonTap(buttonId, spokenText, () {});
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: _focusedButton == buttonId
              ? Border.all(color: Colors.white, width: 2)
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr(title),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  // ───────────── section label ─────────────
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          context.tr(text),
          style: const TextStyle(
            color: _teal,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  // ───────────── pill button for alert speed ─────────────
  Widget _speedPill(String label) {
    final selected = _alertSpeed == label;
    return GestureDetector(
      onTap: () => _handleButtonTap(
        'speed_$label',
        context.tr('{speed} speed', {'speed': context.tr(label)}),
        () {
          setState(() => _alertSpeed = label);
          _save('mizhi_alert_speed', label);
          _applyTts();
        },
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _teal : _pillUnselected,
          borderRadius: BorderRadius.circular(20),
          border: _focusedButton == 'speed_$label'
              ? Border.all(color: Colors.white, width: 2)
              : null,
        ),
        child: Text(
          context.tr(label).toUpperCase(),
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E21),
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: _focusedButton == 'back_button' ? _teal : Colors.white,
          ),
          onPressed: () => _handleButtonTap(
            'back_button',
            'Go back',
            () => Navigator.pop(context),
          ),
        ),
        title: Text(
          context.tr('SETTINGS'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.settings, color: _teal, size: 24),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          // ── VOICE & ALERTS ──
          _sectionLabel('VOICE & ALERTS'),

          // 1 — App and audio language
          _buildSettingRow(
            icon: Icons.language,
            iconColor: _teal,
            title: context.tr('App & Voice Language'),
            buttonId: 'voice_language_row',
            spokenText: context.tr(
              'App & Voice Language, currently {language}',
              {'language': nativeLanguageNames[_language]!},
            ),
            trailing: Theme(
              data: Theme.of(context).copyWith(canvasColor: _cardColor),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _language,
                  style: const TextStyle(color: _teal, fontSize: 14),
                  icon: const Icon(Icons.arrow_drop_down, color: _teal),
                  items: ['English', 'Hindi', 'Tamil', 'Malayalam', 'Telugu']
                      .map(
                        (l) => DropdownMenuItem(
                          value: l,
                          child: Text(
                            nativeLanguageNames[l]!,
                            style: const TextStyle(color: _teal),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _language = v);
                    _save('mizhi_language', v);
                    _applyTts();
                  },
                ),
              ),
            ),
          ),

          // 2 — Alert Speed
          _buildSettingRow(
            icon: Icons.speed,
            iconColor: _teal,
            title: context.tr('Alert Speed'),
            trailing: SizedBox(
              width: 158,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _speedPill('Slow'),
                  _speedPill('Normal'),
                  _speedPill('Fast'),
                ],
              ),
            ),
          ),

          // 3 — Voice Volume
          _buildSettingRow(
            icon: Icons.volume_up,
            iconColor: _teal,
            title: context.tr('Voice Volume'),
            buttonId: 'voice_volume_row',
            spokenText: 'Voice Volume Slider',
            trailing: SizedBox(
              width: 140,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _teal,
                  inactiveTrackColor: _pillUnselected,
                  thumbColor: _teal,
                  overlayColor: _teal.withValues(alpha: 0.2),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _volume,
                  onChanged: (v) {
                    setState(() => _volume = v);
                  },
                  onChangeEnd: (v) {
                    _save('mizhi_volume', v);
                    _applyTts();
                  },
                ),
              ),
            ),
          ),

          // 4 — Vibration
          _buildSettingRow(
            icon: Icons.vibration,
            iconColor: _teal,
            title: context.tr('Vibration'),
            subtitle: context.tr('Silent mode feedback'),
            buttonId: 'vibration_row',
            spokenText: 'Vibration Switch',
            trailing: Switch(
              value: _vibration,
              activeTrackColor: _teal.withValues(alpha: 0.5),
              activeThumbColor: _teal,
              onChanged: (v) {
                setState(() => _vibration = v);
                _save('mizhi_vibration', v);
              },
            ),
          ),

          // ── SAFETY ──
          _sectionLabel('SAFETY'),

          // 5 — Emergency Contact
          _buildSettingRow(
            icon: Icons.emergency,
            iconColor: const Color(0xFFFF4444),
            title: context.tr('Emergency Contact'),
            subtitle: _emergencyContact.isEmpty
                ? context.tr('Not set')
                : _emergencyContact,
            buttonId: 'emergency_contact_row',
            spokenText: context.tr('Emergency Contact, currently {contact}', {
              'contact': _emergencyContact.isEmpty
                  ? context.tr('Not set')
                  : _emergencyContact,
            }),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white54,
              size: 16,
            ),
            onTap: () async {
              final result = await Navigator.pushNamed(
                context,
                '/emergency-contact',
              );
              if (result is String && result.isNotEmpty) {
                setState(() => _emergencyContact = result);
              } else {
                // re-read from prefs in case the screen saved it
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  _emergencyContact =
                      prefs.getString('mizhi_emergency_contact') ?? '';
                });
              }
            },
          ),

          // 5.1 — Live tracking
          _buildLiveTrackingCard(),

          // 6 — Alert Cooldown
          _buildSettingRow(
            icon: Icons.timer,
            iconColor: _teal,
            title: context.tr('Alert Cooldown'),
            subtitle: context.tr('Seconds between same alert'),
            buttonId: 'alert_cooldown_row',
            spokenText: 'Alert Cooldown control',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _cooldownBtn(Icons.remove, () {
                  if (_cooldownSeconds > 1) {
                    setState(() => _cooldownSeconds--);
                    kAlertCooldownSeconds = _cooldownSeconds;
                    _save('mizhi_cooldown', _cooldownSeconds);
                  }
                }, 'Decrease'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '$_cooldownSeconds',
                    style: const TextStyle(
                      color: _teal,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _cooldownBtn(Icons.add, () {
                  if (_cooldownSeconds < 10) {
                    setState(() => _cooldownSeconds++);
                    kAlertCooldownSeconds = _cooldownSeconds;
                    _save('mizhi_cooldown', _cooldownSeconds);
                  }
                }, 'Increase'),
              ],
            ),
          ),

          // ── APPEARANCE ──
          _sectionLabel('APPEARANCE'),

          // 7 — Dark Mode (always on)
          _buildSettingRow(
            icon: Icons.dark_mode,
            iconColor: _teal,
            title: context.tr('Dark Mode'),
            buttonId: 'dark_mode_row',
            spokenText: 'Dark Mode Switch, always on',
            trailing: Switch(
              value: true,
              activeTrackColor: _teal.withValues(alpha: 0.5),
              activeThumbColor: _teal,
              onChanged: null, // always on
            ),
          ),

          // ── ABOUT ──
          _sectionLabel('ABOUT'),

          // 8 — App Version
          _buildSettingRow(
            icon: Icons.info_outline,
            iconColor: _teal,
            title: context.tr('App Version'),
            buttonId: 'app_version_row',
            spokenText: 'App Version Mizhi v1.0.0',
            trailing: Text(
              context.tr('Mizhi v1.0.0'),
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),

          // 9 — Need Assistance card
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F4F45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.headset_mic, color: _teal, size: 32),
                const SizedBox(height: 8),
                Text(
                  context.tr('Need Assistance?'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'Say open Street Smart, open Money Sense, open settings, go back, or change language to Hindi.',
                  ),
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _handleButtonTap(
                    'contact_support',
                    'Voice command help',
                    () {
                      unawaited(AppVoiceService.instance.showHelp());
                    },
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: _focusedButton == 'contact_support'
                          ? Colors.white
                          : _teal,
                      width: _focusedButton == 'contact_support' ? 2 : 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    context.tr('Voice command help'),
                    style: TextStyle(
                      color: _teal,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _cooldownBtn(IconData icon, VoidCallback onTap, String actionName) {
    return GestureDetector(
      onTap: () => _handleButtonTap(
        'cooldown_$actionName',
        context.tr('{action} cooldown', {'action': context.tr(actionName)}),
        onTap,
      ),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: _pillUnselected,
          borderRadius: BorderRadius.circular(8),
          border: _focusedButton == 'cooldown_$actionName'
              ? Border.all(color: Colors.white, width: 2)
              : null,
        ),
        child: Icon(icon, color: _teal, size: 18),
      ),
    );
  }

  Widget _buildLiveTrackingCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: _liveTracking ? Border.all(color: _teal, width: 1) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: _teal, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Live location tracking'),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      context.tr('Emergency contact sees your live location'),
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _liveTracking,
                activeTrackColor: _teal.withValues(alpha: 0.5),
                activeThumbColor: _teal,
                onChanged: (val) async {
                  if (val) {
                    final password = await _showPasswordPrompt();
                    if (password != null && password.isNotEmpty) {
                      setState(() => _liveTracking = true);
                      await _firebaseService.setEnabled(
                        true,
                        password: password,
                      );
                      await _tts.speak('Live location tracking enabled');
                    } else {
                      setState(() => _liveTracking = false);
                    }
                  } else {
                    setState(() => _liveTracking = false);
                    await _firebaseService.setEnabled(false);
                    await _tts.speak('Live location tracking disabled');
                  }
                },
              ),
            ],
          ),

          if (_liveTracking) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E21),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Share this link with emergency contact:'),
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _firebaseService.trackingUrl,
                    style: const TextStyle(
                      color: _teal,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Copy link button
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: _firebaseService.trackingUrl),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('Link copied!')),
                          backgroundColor: _teal,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _teal,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, color: Colors.black, size: 16),
                          SizedBox(width: 6),
                          Text(
                            context.tr('Copy link'),
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('Updates every 30 seconds. Free, uses internet.'),
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Future<String?> _showPasswordPrompt() async {
    String tempPass = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _cardColor,
          title: Text(
            context.tr('Set Tracking Password'),
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: context.tr('Enter a secure password'),
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _teal),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _teal),
              ),
            ),
            obscureText: false,
            onChanged: (v) => tempPass = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                context.tr('Cancel'),
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, tempPass),
              child: Text(
                context.tr('Confirm'),
                style: TextStyle(color: _teal),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_settingsChanged);
    _tts.stop();
    super.dispose();
  }
}
