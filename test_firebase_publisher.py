"""
Firebase Realtime Database Test Publisher
------------------------------------------
Sends simulated vital signs (BPM, SpO2, Temperature, isDanger)
to the Firebase Realtime Database node `/patient`.

Usage:
    python test_firebase_publisher.py
"""

import time
import random
import urllib.request
import json

# Your Firebase Realtime Database URL from google-services.json
DATABASE_URL = "https://patient-monitor-1bf49-default-rtdb.firebaseio.com"
PATIENT_ENDPOINT = f"{DATABASE_URL}/patient.json"

def send_vitals(bpm, spo2, temp, is_danger, status):
    payload = {
        "bpm": bpm,
        "spo2": spo2,
        "temp": round(temp, 1),
        "isDanger": is_danger,
        "status": status,
        "patientId": "PT-9042",
        "patientName": "Eleanor Vance",
        "lastUpdated": int(time.time() * 1000)
    }
    
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        PATIENT_ENDPOINT,
        data=data,
        headers={"Content-Type": "application/json"},
        method="PUT"
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                print(f"[✓ LIVE RTDB UPDATE] BPM: {bpm} | SpO2: {spo2}% | Temp: {round(temp, 1)}°C | Danger: {is_danger} ({status})")
            else:
                print(f"[!] Server responded with status: {response.status}")
    except Exception as e:
        print(f"[!] Error updating Firebase RTDB: {e}")
        print("    Note: Check your Firebase Database Rules to allow write access: { \"rules\": { \".read\": true, \".write\": true } }")

def main():
    print("=" * 65)
    print("  ICU Patient Telemetry Publisher -> Firebase /patient")
    print(f"  Target: {PATIENT_ENDPOINT}")
    print("=" * 65)
    print("Streaming live telemetry every 3 seconds (Press Ctrl+C to stop)...\n")

    counter = 0
    try:
        while True:
            counter += 1
            # Every 10 iterations, simulate a 2-cycle critical event
            if 8 <= (counter % 12) <= 9:
                bpm = random.randint(132, 145)
                spo2 = random.randint(86, 89)
                temp = random.uniform(38.8, 39.5)
                is_danger = True
                status = "Critical Tachycardia & Hypoxia"
            else:
                bpm = random.randint(68, 78)
                spo2 = random.randint(96, 99)
                temp = random.uniform(36.5, 37.0)
                is_danger = False
                status = "Normal Sinus"

            send_vitals(bpm, spo2, temp, is_danger, status)
            time.sleep(3)
    except KeyboardInterrupt:
        print("\nPublisher stopped.")

if __name__ == "__main__":
    main()
