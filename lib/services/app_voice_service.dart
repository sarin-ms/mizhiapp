import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mizhi/l10n/app_localizations.dart';
import 'package:mizhi/l10n/language_catalog.dart';
import 'package:mizhi/services/app_audio.dart';
import 'package:mizhi/services/app_settings.dart';
import 'package:mizhi/services/voice_commands.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();
final appRouteObserver = AppRouteObserver();

class AppRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  void reset() => _routes.clear();
  void _changed() {
    final pages = _routes.whereType<PageRoute<dynamic>>();
    AppVoiceService.instance.routeChanged(
      pages.isEmpty ? null : pages.last.settings.name,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _changed();
  }
}

class _CameraHooks {
  final Object owner;
  final Future<void> Function() pause;
  final Future<void> Function() resume;
  final Future<bool> Function(bool enabled) flashlight;
  _CameraHooks(this.owner, this.pause, this.resume, this.flashlight);
}

/// A single foreground recognizer owns commands, independent of the active page.
class AppVoiceService extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = AppVoiceService();
  final SpeechToText _speech = SpeechToText();
  final AppSettings settings;
  final AppAudio audio;
  final Map<String, _CameraHooks> _cameras = {};
  Future<void> _cameraTransition = Future.value();
  Future<void>? _initialization;
  Timer? _restart;
  bool _ready = false;
  bool _foreground = true;
  bool _executing = false;
  bool _started = false;
  bool _starting = false;
  bool _blocked = false;
  int _generation = 0;
  int _errors = 0;
  String? _localeId;
  String? currentRoute;
  String status = 'Tap microphone to speak';
  String? _lastCommand;
  DateTime _lastCommandAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _commandWindowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String _language = 'English';

  AppVoiceService({AppSettings? settings, AppAudio? audio})
    : settings = settings ?? AppSettings.instance,
      audio = audio ?? AppAudio.instance;

  bool get listening => _speech.isListening;
  bool get acceptingCommand =>
      _executing || DateTime.now().isBefore(_commandWindowUntil);
  bool cameraActive(String route) => _foreground && currentRoute == route;
  bool get availableOnPage =>
      currentRoute != null && !['/', '/permissions'].contains(currentRoute);
  bool get _canListen =>
      _started &&
      _foreground &&
      availableOnPage &&
      !_executing &&
      !audio.speaking &&
      !_blocked;

  void start() {
    if (_started) return;
    _started = true;
    _blocked = false;
    _foreground = true;
    _localeId = null;
    if (!_ready) _initialization = null;
    _language = settings.language;
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_settingsChanged);
    audio.beforeSpeak = (_) => pause();
    audio.afterSpeak = () => _schedule();
    _schedule();
  }

  void shutdown() {
    _started = false;
    _restart?.cancel();
    settings.removeListener(_settingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    audio.beforeSpeak = null;
    audio.afterSpeak = null;
    currentRoute = null;
    unawaited(pause());
  }

  void registerCamera(
    String route,
    Object owner, {
    required Future<void> Function() pause,
    required Future<void> Function() resume,
    required Future<bool> Function(bool) flashlight,
  }) => _cameras[route] = _CameraHooks(owner, pause, resume, flashlight);

  void unregisterCamera(String route, Object owner) {
    if (identical(_cameras[route]?.owner, owner)) _cameras.remove(route);
  }

  void routeChanged(String? route) {
    if (route == currentRoute) return;
    final previous = _cameras[currentRoute];
    currentRoute = route;
    final next = _cameras[route];
    unawaited(pause());
    _cameraTransition = _cameraTransition
        .then((_) async {
          await previous?.pause();
          if (currentRoute == route) await next?.resume();
        })
        .catchError((Object e) {
          debugPrint('Camera transition error: $e');
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_started) return;
      notifyListeners();
      _schedule();
    });
  }

  void _settingsChanged() {
    if (_language != settings.language) {
      _language = settings.language;
      _localeId = null;
      _blocked = false;
      unawaited(pause());
      unawaited(
        audio.stop().then((_) => audio.configure()).then((_) => _schedule()),
      );
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      unawaited(pause());
      unawaited(_cameras[currentRoute]?.pause() ?? Future.value());
      unawaited(audio.stop());
    } else {
      _blocked = false;
      if (!_ready) _initialization = null;
      unawaited(_cameras[currentRoute]?.resume() ?? Future.value());
      unawaited(audio.configure(force: true));
      _schedule();
    }
  }

  Future<void> pause() async {
    _restart?.cancel();
    _generation++;
    if (_ready) await _speech.cancel();
  }

  void _schedule() {
    if (!_canListen || _restart?.isActive == true) return;
    final delay = Duration(
      milliseconds: _errors == 0 ? 700 : (1500 * _errors).clamp(1500, 15000),
    );
    _restart = Timer(delay, () {
      unawaited(listen());
    });
  }

  Future<void> listen({bool requestPermission = false}) async {
    if (requestPermission) {
      _blocked = false;
      _errors = 0;
      if (!_ready) _initialization = null;
      _commandWindowUntil = DateTime.now().add(const Duration(seconds: 10));
    }
    if (!_canListen || _speech.isListening || _starting) return;
    _starting = true;
    final attempt = _generation;
    _restart?.cancel();
    try {
      var permission = await Permission.microphone.status;
      if (!permission.isGranted && requestPermission) {
        permission = await Permission.microphone.request();
      }
      if (!permission.isGranted) {
        _blocked = true;
        _setStatus('Microphone permission required');
        return;
      }
      _initialization ??= _initialize();
      await _initialization;
      if (!_ready || !_canListen || attempt != _generation) return;
      final locale = _localeId ?? await _resolveLocale();
      if (!_canListen || attempt != _generation) return;
      _localeId = locale;
      if (_localeId == null) {
        _blocked = true;
        _setStatus('Speech recognition unavailable for {language}');
        return;
      }
      final generation = ++_generation;
      await _speech.listen(
        localeId: _localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
        ),
        onResult: (result) {
          if (generation == _generation) unawaited(handleResult(result));
        },
      );
      if (generation == _generation) {
        _setStatus(
          _speech.isListening ? 'Listening...' : 'Tap microphone to speak',
        );
      }
    } catch (e) {
      _errors++;
      _setStatus('Speech recognition unavailable');
      debugPrint('Voice recognition error: $e');
      _schedule();
    } finally {
      _starting = false;
      if (!_speech.isListening) _schedule();
    }
  }

  Future<void> _initialize() async {
    _ready = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _setStatus('Tap microphone to speak');
          _schedule();
        }
      },
      onError: handleError,
    );
    if (!_ready) {
      _blocked = true;
      _setStatus('Speech recognition unavailable');
    }
  }

  void handleError(SpeechRecognitionError error) {
    if (!_canListen) return;
    // Android marks even silence and busy-session errors as permanent.
    const silence = {'error_no_match', 'error_speech_timeout'};
    const recoverable = {
      ...silence,
      'error_busy',
      'error_network',
      'error_network_timeout',
      'error_server',
      'error_server_disconnected',
      'error_retry',
      'error_audio',
    };
    _errors = silence.contains(error.errorMsg) ? 0 : _errors + 1;
    _blocked = error.permanent && !recoverable.contains(error.errorMsg);
    _setStatus(
      silence.contains(error.errorMsg)
          ? 'Tap microphone to speak'
          : 'Speech recognition unavailable',
    );
    _schedule();
  }

  Future<String?> _resolveLocale() async {
    final requested = languageCodes[settings.language]!
        .replaceAll('-', '_')
        .toLowerCase();
    final locales = await _speech.locales();
    for (final locale in locales) {
      if (locale.localeId.replaceAll('-', '_').toLowerCase() == requested) {
        return locale.localeId;
      }
    }
    final prefix = requested.split('_').first;
    for (final locale in locales) {
      if (locale.localeId.replaceAll('-', '_').toLowerCase().split('_').first ==
          prefix) {
        return locale.localeId;
      }
    }
    return null;
  }

  void _setStatus(String value) {
    if (status == value) return;
    status = value;
    notifyListeners();
  }

  Future<void> handleResult(SpeechRecognitionResult result) async {
    if (!_canListen) return;
    if (!result.finalResult) {
      if (result.recognizedWords.isNotEmpty) {
        _commandWindowUntil = DateTime.now().add(const Duration(seconds: 4));
      }
      return;
    }
    final text = normalizeCommand(result.recognizedWords);
    final now = DateTime.now();
    if (text == _lastCommand &&
        now.difference(_lastCommandAt) < const Duration(seconds: 2)) {
      return;
    }
    final command = parseVoiceCommand(text);
    if (command == null) {
      _setStatus('Command not recognized');
      return;
    }
    _lastCommand = text;
    _lastCommandAt = now;
    _errors = 0;
    _executing = true;
    try {
      await pause();
      await execute(command);
    } catch (e) {
      debugPrint('Voice command error: $e');
      await audio.say('Unable to complete command');
    } finally {
      _executing = false;
      _commandWindowUntil = DateTime.fromMillisecondsSinceEpoch(0);
      _schedule();
    }
  }

  Future<void> navigate(String route) async {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null || currentRoute == route) return;
    await _cameraTransition;
    await _cameras[currentRoute]?.pause();
    if (route == '/home') {
      navigator.popUntil((r) => r.settings.name == '/home' || r.isFirst);
      if (currentRoute != '/home') {
        unawaited(navigator.pushReplacementNamed('/home'));
      }
    } else if (route == '/settings' || route == '/emergency-contact') {
      unawaited(navigator.pushNamed(route));
    } else {
      unawaited(
        navigator.pushNamedAndRemoveUntil(
          route,
          (r) => r.settings.name == '/home' || r.isFirst,
        ),
      );
    }
  }

  Future<void> execute(VoiceCommand command) async {
    switch (command.action) {
      case VoiceAction.street:
        await _open('/street-smart', 'Street Smart');
      case VoiceAction.money:
        await _open('/money-sense', 'Money Sense');
      case VoiceAction.settings:
        await _open('/settings', 'Settings');
      case VoiceAction.emergencyContact:
        await _open('/emergency-contact', 'Emergency Contact');
      case VoiceAction.home:
        await _open('/home', 'Home');
      case VoiceAction.back:
        final navigator = appNavigatorKey.currentState;
        if (navigator == null || !navigator.canPop()) {
          await audio.say('Already on Home');
          return;
        }
        await audio.say('Going back');
        await _cameraTransition;
        await _cameras[currentRoute]?.pause();
        await navigator.maybePop();
      case VoiceAction.language:
        await settings.save('mizhi_language', command.value!);
        await audio.configure();
        await audio.say('Language changed to {language}', {
          'language': nativeLanguageNames[settings.language]!,
        });
      case VoiceAction.speed:
        await settings.save('mizhi_alert_speed', command.value!);
        await audio.say('Speed changed to {speed}', {
          'speed': translate(command.value!, settings.language),
        });
      case VoiceAction.volumeUp:
        await _setVolume(settings.volume + 0.1);
      case VoiceAction.volumeDown:
        await _setVolume(settings.volume - 0.1);
      case VoiceAction.volume:
        await _setVolume(command.number! / 100);
      case VoiceAction.cooldown:
        await settings.save('mizhi_cooldown', command.number!);
        await audio.say('Alert Cooldown');
      case VoiceAction.vibrationOn:
        await settings.save('mizhi_vibration', true);
        await audio.say('Vibration enabled');
      case VoiceAction.vibrationOff:
        await settings.save('mizhi_vibration', false);
        await audio.say('Vibration disabled');
      case VoiceAction.voiceOn:
        await settings.save('mizhi_voice_feedback', true);
        await audio.say('Voice feedback enabled');
      case VoiceAction.voiceOff:
        await audio.say('Voice feedback disabled');
        await settings.save('mizhi_voice_feedback', false);
      case VoiceAction.flashOn:
        await _flashlight(true);
      case VoiceAction.flashOff:
        await _flashlight(false);
      case VoiceAction.help:
        await showHelp();
      case VoiceAction.emergencyCall:
        await _callEmergencyContact();
    }
  }

  Future<void> _open(String route, String title) async {
    await audio.say('Opening {mode}', {
      'mode': translate(title, settings.language),
    });
    await navigate(route);
  }

  Future<void> _setVolume(double value) async {
    await settings.save('mizhi_volume', value.clamp(0.0, 1.0));
    await audio.say('Volume changed to {volume} percent', {
      'volume': (settings.volume * 100).round(),
    });
  }

  Future<void> _flashlight(bool enabled) async {
    final camera = _cameras[currentRoute];
    if (camera == null) {
      await audio.say('Open a camera mode to use the flashlight');
      return;
    }
    final changed = await camera.flashlight(enabled);
    await audio.say(
      changed
          ? (enabled ? 'Flashlight on' : 'Flashlight off')
          : 'Flashlight unavailable',
    );
  }

  Future<void> showHelp() async {
    const help =
        'Say open Street Smart, open Money Sense, open settings, go back, or change language to Hindi.';
    final context = appNavigatorKey.currentContext;
    if (context != null) {
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('Voice command help')),
            content: Text(context.tr(help)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr('Confirm')),
              ),
            ],
          ),
        ),
      );
    }
    await audio.say(help);
  }

  Future<void> _callEmergencyContact() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('mizhi_emergency_phone')?.trim() ?? '';
    final name = prefs.getString('mizhi_emergency_contact')?.trim() ?? '';
    if (phone.isEmpty) {
      await audio.say('No emergency contact saved. Please add one.');
      await navigate('/emergency-contact');
      return;
    }
    if (name.isEmpty) {
      await audio.say('Calling emergency contact');
    } else {
      await audio.say('Calling {name}', {'name': name});
    }
    await launchUrl(
      Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')),
      mode: LaunchMode.externalApplication,
    );
  }
}

class VoiceControlBar extends StatelessWidget {
  const VoiceControlBar({super.key});
  @override
  Widget build(BuildContext context) {
    final service = AppVoiceService.instance;
    final audio = AppAudio.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([service, audio]),
      builder: (context, _) {
        if (!service.availableOnPage) return const SizedBox.shrink();
        final language = nativeLanguageNames[AppSettings.instance.language]!;
        final status = audio.voiceUnavailable
            ? 'Install a {language} voice in device settings'
            : service.status;
        return Material(
          color: const Color(0xFF0A0E21),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: context.tr('Voice commands'),
                  icon: Icon(
                    service.listening ? Icons.mic : Icons.mic_none,
                    color: Colors.tealAccent,
                  ),
                  onPressed: () async {
                    await audio.stop();
                    await service.listen(requestPermission: true);
                  },
                ),
                Expanded(
                  child: Text(
                    context.tr(status, {'language': language}),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Voice command help'),
                  icon: const Icon(Icons.help_outline, color: Colors.white70),
                  onPressed: service.showHelp,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
