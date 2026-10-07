/*
  ==============================================================
  ESP32 Patient Monitoring - Firebase Realtime Database Sync
  ==============================================================
  Project: Patient Monitor
  Database Node: /patient
  Firebase URL: https://patient-monitor-1bf49-default-rtdb.firebaseio.com

  Libraries Required:
  - Standard ESP32 Core (WiFi.h, HTTPClient.h, WiFiClientSecure.h)
  - Optional for real sensors:
      * MAX30105 / MAX30102 library (SparkFun MAX3010x)
      * OneWire & DallasTemperature (for DS18B20)
  ==============================================================
*/

#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>

// 1. ඔබේ Wi-Fi විස්තර ඇතුළත් කරන්න
const char* ssid     = "YOUR_WIFI_NAME";
const char* password = "YOUR_WIFI_PASSWORD";

// 2. ඔබගේ Firebase Realtime Database Endpoint එක
const char* firebaseUrl = "https://patient-monitor-1bf49-default-rtdb.firebaseio.com/patient.json";

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n--- ESP32 Patient Monitor Initializing ---");

  // Wi-Fi සම්බන්ධ කිරීම
  WiFi.begin(ssid, password);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\n[✓] Wi-Fi Connected!");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());
}

void loop() {
  if (WiFi.status() == WL_CONNECTED) {
    // -------------------------------------------------------------
    // මෙතනට ඔබේ Sensors (MAX30102 / DS18B20) වලින් ගන්නා අගයන් දමන්න
    // (පරීක්ෂා කිරීම සඳහා random/sample අගයන් සාදා ඇත)
    // -------------------------------------------------------------
    int bpm = random(72, 85);         // උදා: Heart rate (60 - 100)
    int spo2 = random(96, 100);       // උදා: Blood Oxygen (95 - 100%)
    float temperature = 36.6 + (random(0, 10) / 10.0); // උදා: 36.6 - 37.5 °C

    // අවදානම් තත්ත්වයක් පරීක්ෂා කිරීම (Thresholds check)
    bool isDanger = false;
    String status = "Normal";

    if (bpm > 110 || bpm < 50 || spo2 < 93 || temperature > 38.0) {
      isDanger = true;
      status = "Critical Hazard Detected";
    }

    // JSON Payload එක සෑදීම
    String jsonPayload = "{";
    jsonPayload += "\"bpm\":" + String(bpm) + ",";
    jsonPayload += "\"spo2\":" + String(spo2) + ",";
    jsonPayload += "\"temp\":" + String(temperature, 1) + ",";
    jsonPayload += "\"isDanger\":" + String(isDanger ? "true" : "false") + ",";
    jsonPayload += "\"status\":\"" + status + "\",";
    jsonPayload += "\"patientId\":\"PT-9042\",";
    jsonPayload += "\"patientName\":\"Eleanor Vance\"";
    jsonPayload += "}";

    // Firebase වෙත HTTP PUT request එක යැවීම
    WiFiClientSecure client;
    client.setInsecure(); // SSL Certificate bypass for simple Firebase RTDB REST

    HTTPClient https;
    if (https.begin(client, firebaseUrl)) {
      https.addHeader("Content-Type", "application/json");

      int httpResponseCode = https.PUT(jsonPayload);

      if (httpResponseCode > 0) {
        Serial.printf("[Firebase Updated] Code: %d | BPM: %d | SpO2: %d%% | Temp: %.1f C | Danger: %s\n",
                      httpResponseCode, bpm, spo2, temperature, isDanger ? "YES" : "NO");
      } else {
        Serial.printf("[!] Error sending data: %s\n", https.errorToString(httpResponseCode).c_str());
      }
      https.end();
    }
  } else {
    Serial.println("[!] Wi-Fi disconnected. Reconnecting...");
    WiFi.reconnect();
  }

  // තත්පර 3 කට වරක් දත්ත Firebase වෙත යවන්න
  delay(3000);
}
