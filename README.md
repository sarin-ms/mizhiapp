# Mizhi

**Mizhi** is an AI-powered Flutter application designed to support visually impaired users with everyday activities through on-device object detection, Indian currency recognition, voice assistance, and emergency location sharing.

The object-detection and currency-recognition models run on the device. Speech recognition and location sharing use device services and may require an internet connection.

> **Project goal:** Make everyday interactions more accessible through practical AI features and localized audio feedback.

## Table of Contents

- [Features](#features)
  - [Street Smart — Object Detection](#1-street-smart--object-detection)
  - [Money Sense — Currency Recognition](#2-money-sense--currency-recognition)
  - [Voice Commands](#3-voice-commands)
  - [Emergency SOS](#4-emergency-sos)
  - [Languages and Preferences](#5-languages-and-preferences)
- [Technology](#technology)
- [Performance and Mobile Optimization](#performance-and-mobile-optimization)
- [Getting Started](#getting-started)
- [Build an APK](#build-an-apk)
- [Performance Benchmark](#performance-benchmark)
- [Screenshots](#screenshots)
- [Demo](#demo)
- [Project Notes](#project-notes)


## Features

### 1. Street Smart — Object Detection

Street Smart uses an on-device object-detection model to recognize **80 everyday object classes**, including people, vehicles, laptops, bottles, phones, keyboards, chairs, bags, kitchen items, and animals.

- Displays detected object names and bounding boxes.
- Confirms weaker detections across successive frames.
- Provides prioritized audio feedback.
- Runs camera processing and inference in a persistent background worker to help keep the preview responsive.
- Adapts detection updates to device processing speed, with a 120 ms minimum interval. This interval is separate from the camera preview frame rate.

### 2. Money Sense — Currency Recognition

Money Sense uses a custom deep learning classification model to recognize Indian Rupee denominations.

- Performs model inference on the device.
- Announces the recognized denomination through localized audio feedback.
- Uses haptic feedback to reinforce the result.

### 3. Voice Commands

Voice commands provide hands-free access to common app actions. After microphone permission is granted, users can speak a complete command. Tapping the microphone starts another recognition session and gives the command priority over automatic camera announcements.

| Action | Example command |
| --- | --- |
| Open a mode | “Open Street Smart” or “Open Money Sense” |
| Navigate | “Open settings”, “Go back”, or “Go home” |
| Change language | “Change language to Hindi” |
| Adjust volume | “Volume up”, “Volume down”, or “Set volume to 50 percent” |
| Adjust speech | “Speak slower”, “Speak faster”, or “Set speed to normal” |
| Change feedback | “Vibration off” or “Voice on” |
| Camera light | “Flashlight on” or “Flashlight off” |
| Alert interval | “Set alert cooldown to 4 seconds” |

The app also supports native command examples in the selected language:

- Hindi: “सेटिंग्स खोलो”
- Tamil: “அமைப்புகள் திற”
- Malayalam: “ക്രമീകരണങ്ങൾ തുറക്കുക”
- Telugu: “సెట్టింగులు తెరువు”

One foreground speech recognizer serves all screens. It pauses during spoken feedback and restarts after normal silence. Camera modes release the camera before navigation and resume it when the user returns.

Voice recognition requires a speech recognizer on the device. Spoken output requires a text-to-speech voice for the selected language. When either is unavailable, the app displays a localized status. Missing voices can be installed through the device's text-to-speech settings. System permission dialogs follow the operating system language.

### 4. Emergency SOS

The Emergency/SOS feature integrates Firebase to share the user's geolocation with listed emergency contacts when help is needed. Location tracking shares one service and prevents overlapping uploads.

### 5. Languages and Preferences

Mizhi supports five app and audio languages:

- English
- Hindi
- Tamil
- Malayalam
- Telugu

Changing the language updates screen text, dialogs, object names, currency announcements, spoken feedback, and the speech-recognition locale. Language and other preferences are saved across app restarts.

## Technology

| Area | Technology / approach |
| --- | --- |
| Mobile application | Flutter and Dart |
| On-device machine learning | TensorFlow Lite |
| Object detection | On-device object-detection model (80 classes) |
| Currency recognition | Custom deep learning classification model |
| Emergency location sharing | Firebase and device location services |
| Voice interaction | Device speech recognition and text-to-speech services |
| Feedback | Audio announcements and haptic vibration |
| Camera processing | Background worker / isolates and reusable image buffers |

## Performance and Mobile Optimization

Both camera models run in persistent background isolates. The preprocessing pipeline reuses RGB input buffers and writes directly to allocated TensorFlow Lite tensors. This avoids nested image lists and repeated native input/output copies.

To prevent work from accumulating when camera frames arrive faster than inference can complete:

- Each mode admits only one frame at a time and drops intervening frames.
- Street Smart adapts detection updates to device processing speed.
- Money Sense adapts its scan interval to processing time, starting at 250 ms. This is independent of camera preview FPS.
- Street Smart updates detection boxes and status without rebuilding the camera preview and controls on every scan.
- Money Sense redraws results only when the denomination or displayed confidence changes.
- Camera streams and scanning animations pause when navigating away from a camera mode or backgrounding the app.
- Location tracking uses one shared service and prevents overlapping uploads.

Only the two active models and their labels are bundled.

## Getting Started

### Prerequisites

- Flutter SDK installed and configured.
- Android device or emulator configured for Flutter development.
- Git installed.

Check your Flutter setup with:

```bash
flutter doctor
```

### Installation

```bash
# Clone the repository
git clone https://github.com/sarin-ms/mizhiapp.git

# Enter the project directory
cd mizhiapp

# Install Flutter dependencies
flutter pub get

# Generate launcher icons (optional)
dart run flutter_launcher_icons

# Run on an attached device or emulator
flutter run
```

Grant the requested camera, microphone, and location permissions when testing the corresponding features.

## Build an APK

For a release APK split by supported Android ABIs, run:

```bash
flutter build apk --release --split-per-abi
```

Choose the output that matches the target device:

- `app-arm64-v8a-release.apk` for a 64-bit ARM device.
- `app-armeabi-v7a-release.apk` for an older 32-bit ARM device.

**Signing note:** The current release configuration uses a development signing key for local testing. Configure production signing before distributing the app through an app store or other production channel.

## Performance Benchmark

Run the preprocessing benchmark with:

```bash
flutter test tool/mobile_preprocessing_benchmark.dart --reporter expanded
```

The benchmark compares the previous currency-image conversion and nested tensor-allocation path with the reusable-buffer implementation, and verifies that the resulting RGB pixels are identical.

One Windows run recorded the following median preprocessing times:

| Implementation | Median preprocessing time |
| --- | ---: |
| Previous implementation | 8.31 ms |
| Reusable-buffer implementation | 2.86 ms |

This benchmark measures preprocessing only. It excludes model inference, isolate transport, and camera capture, and it does **not** predict mobile-device FPS or overall app performance.

For real-device FPS, CPU, memory, and battery measurements, run the app in profile mode on the target phone:

```bash
flutter run --profile
```

Desktop tests can verify conversion and lifecycle behavior, but they do not establish physical-device performance.

## Google AI Usage

### Tools and services

- **Antigravity IDE** — used as a development environment to support implementation and integration across app modules.
- **Stitch AI** — used to support AI-assisted development workflows and interface iteration.
- **Firebase** — used for backend connectivity in emergency GPS location sharing.
- **Google Text-to-Speech** — used to provide spoken guidance and feedback.

AI is central to Mizhi's accessibility features, particularly object detection and currency recognition. The app combines on-device machine-learning inference with speech, haptic, and location services.

## Screenshots

![Mizhi screenshot 1](./assets/Screenshot_mizhi(1).jpeg)

![Mizhi screenshot 2](./assets/Screenshot_mizhi(2).jpeg)

![Mizhi screenshot 3](./assets/Screenshot_mizhi(3).jpeg)

![Mizhi screenshot 4](./assets/Screenshot_mizhi(4).jpeg)

![Mizhi screenshot 5](./assets/Screenshot_mizhi(5).jpeg)

## Demo

[Watch the Mizhi demo](https://drive.google.com/file/d/1-6D6lfRF0qBgdeorD8Up-osKMurLOk-x/view?usp=drivesdk)

## Project Notes

- Object detection and currency classification run on-device.
- Speech recognition and location sharing use device services and may require internet access.
- Availability of speech recognition and text-to-speech voices depends on the device and its installed language services.
- The preprocessing benchmark is a single Windows measurement, not a mobile performance claim.
- Production distribution requires production app signing.

---

**Mizhi — making everyday experiences more accessible through AI.**
