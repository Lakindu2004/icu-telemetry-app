# 🩺 Flutter ICU Patient Telemetry & Monitoring System

A comprehensive, real-time Flutter ICU/Telehealth Patient Monitoring dashboard integrated with **Firebase Realtime Database** at node `/patient`.

---

## 🌟 Advanced Clinical Features

### 1. Multi-Bed Ward Selector
- Seamlessly switch between hospital beds (**Bed 01 (ICU-A)**, **Bed 02 (Cardiology)**, **Bed 03 (Trauma)**, **Bed 04 (CCU)**).
- Default Bed 01 connects directly to your hardware node `/patient`.

### 2. Audible & Haptic Alarm System
- **Real-Time Hazard Audio**: Emits standard medical alert tones (`SystemSound.play(SystemSoundType.alert)`) and heavy haptic vibration pulses whenever `isDanger` is true.
- **Mute / Arm Control**: Easily silence audible alarms via the top navigation bar with a single tap.

### 3. Historical Telemetry Trend Chart
- Custom Bezier line chart tracking rolling vital readings with gradient fills and threshold gridlines.
- Interactive metric switcher (**BPM**, **SpO2**, **Temperature**).
- Real-time statistical summary chips (**Current**, **Min**, **Avg**, **Max**).

### 4. Dynamic Critical Alert Banner
- Automatically activates whenever `isDanger` is true or if physiological thresholds are breached.
- Radiant crimson pulsing alert with condition diagnosis (e.g., Tachycardia, Hypoxia, Pyrexia/Fever).
- Shows "Stable" emerald-green badge when patient vitals rest within calibrated ranges.

### 5. Clinical Threshold Calibration
- Slide-up bottom sheet modal to adjust clinical thresholds:
  - **Max Heart Rate** (BPM)
  - **Min Blood Oxygen** (SpO2 %)
  - **Max Body Temperature** (°C)

### 6. Clinical Incident Log & Emergency Dispatch
- Automatically logs threshold transitions and critical events with millisecond-accurate timestamps.
- One-tap action buttons: **Call Nurse Station** and **Code Blue Alert**.

### 7. Temperature Unit Conversion
- Instant **°C ⇄ °F** unit toggle from the AppBar.

---

## 📦 Project Architecture

- [lib/main.dart](file:///c:/Users/Lakindu/Desktop/edp%201/lib/main.dart): Full ICU dashboard with multi-bed selector, audible alarms, trend chart, and telemetry listeners.
- [lib/firebase_options.dart](file:///c:/Users/Lakindu/Desktop/edp%201/lib/firebase_options.dart): Firebase credentials generated from `google-services.json`.
- [android/app/google-services.json](file:///c:/Users/Lakindu/Desktop/edp%201/android/app/google-services.json): Firebase configuration for package `com.example.patient_monitor`.
- [test_firebase_publisher.py](file:///c:/Users/Lakindu/Desktop/edp%201/test_firebase_publisher.py): Python test publisher streaming live vitals to Firebase RTDB `/patient`.

---

## 🚀 Testing & Running

### Step 1: Simulate Live Data to Firebase
You can stream live sensor data directly to your Firebase database using the included Python publisher:

```bash
python test_firebase_publisher.py
```

### Step 2: Run the Flutter App
Once your Flutter SDK is configured in your `PATH`:

```bash
# Get dependencies
flutter pub get

# Run on Android device / emulator
flutter run

# Or run on Chrome / Web
flutter run -d chrome
```
