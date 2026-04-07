# Mizhi

## Problem Statement

Visually impaired individuals face significant challenges when navigating dynamic, unfamiliar environments and managing everyday tasks independently. Key difficulties include avoiding moving obstacles, orienting themselves safely on streets, and quickly identifying the denomination of paper currency without assistance. Traditional navigation aids lack the real-time contextual awareness necessary to identify specific objects and provide actionable, localized feedback.

## Project Description

Mizhi is an AI-powered mobile application built in Flutter designed strictly to solve accessibility and safety challenges for the visually impaired. It operates entirely on the edge to ensure real-time responsiveness without relying on internet connectivity. The core solution features:

- **Street Smart (Object Detection):** Uses the device camera to constantly scan the environment for people, cars, buses, and trucks. By mapping the bounding boxes of detected objects to the camera's frame, the app calculates directional audio feedback (e.g., "Car ahead, move left" or "Person ahead, move right") to help the user navigate obstacles.
- **Money Sense (Currency Classification):** Employs a custom deep learning classification model to quickly and accurately identify Indian Rupee denominations, using localized audio and haptic feedback to verify the result to the user.
- **Emergency / SOS Integration:** Integrates Firebase to instantly share the user's geolocation with listed emergency contacts when help is needed.

---

## Google AI Usage

### Tools / Models Used

- **TensorFlow Lite (`tflite_flutter`)**
- **Custom TFLite Object Detection Model (`mizhi_street_smart.tflite`)** (SSD/RetinaNet architecture optimized for edge ML)
- **Custom TFLite Image Classification Model (`mizhi_money_sense.tflite`)**
- **Google Gemini 3.1 Pro (High)**

### How Google AI Was Used

AI is the foundation of Mizhi's accessibility features:

1. **On-Device Machine Learning (TensorFlow Lite):** Real-time image buffers from the device's camera are continuously processed through our custom TensorFlow Lite models directly on the edge. This provides rapid, offline inferences for object detection and currency classification—critical for visually impaired users who cannot wait for cloud latency.
2. **Development Assistance with Gemini:** Google Gemini 3.1 Pro was used extensively during the hackathon to architect and debug the complex Flutter pipeline. Gemini AI assisted with migrating the RetinaNet object detection workflows, parsing custom anchor boxes, writing the complex cross-platform Image Buffer conversions (from YUV420 to Uint8/Float32), and resolving integration bugs.

---

## Proof of Google AI Usage

_(Note: Please ensure you drop your proof screenshots in the `/proof` directory)_

![AI Proof](./proof/screenshot1.png)

---

## Screenshots

_(Note: Please ensure your application screenshots are placed in the `/assets` directory)_

![Screenshot1](./assets/screenshot1.png)  
![Screenshot2](./assets/screenshot2.png)

---

## Demo Video

Upload your demo video to Google Drive and paste the shareable link here (max 3 minutes).
[Watch Demo](#)

---

## Installation Steps

```bash
# Clone the repository
git clone https://github.com/sarin-ms/mizhi.git

# Go to project folder
cd mizhi

# Install Flutter dependencies
flutter pub get

# Generate Launcher Icons (Optional)
dart run flutter_launcher_icons

# Run the project on an attached device or emulator
flutter run
```
