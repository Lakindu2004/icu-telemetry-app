import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseInitialized = true;
  } catch (e) {
    debugPrint('Firebase init fallback: $e');
    try {
      await Firebase.initializeApp();
      firebaseInitialized = true;
    } catch (_) {
      firebaseInitialized = false;
    }
  }

  runApp(PatientMonitoringApp(isFirebaseConfigured: firebaseInitialized));
}

/// Root Application
class PatientMonitoringApp extends StatelessWidget {
  final bool isFirebaseConfigured;

  const PatientMonitoringApp({super.key, required this.isFirebaseConfigured});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICU Telemetry & Patient Monitor',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080C14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF3366),
          surface: Color(0xFF111726),
        ),
        cardColor: const Color(0xFF111726),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1322),
          elevation: 0,
        ),
      ),
      home: PatientMonitorScreen(initialFirebaseStatus: isFirebaseConfigured),
    );
  }
}

/// Bed Definition for Multi-Patient Selector
class PatientBed {
  final String id;
  final String bedNumber;
  final String patientName;
  final String department;
  final String firebasePath;

  const PatientBed({
    required this.id,
    required this.bedNumber,
    required this.patientName,
    required this.department,
    required this.firebasePath,
  });
}

/// Historical Data Point Model
class VitalHistoryPoint {
  final DateTime timestamp;
  final int bpm;
  final int spo2;
  final double temperature;
  final bool isDanger;

  VitalHistoryPoint({
    required this.timestamp,
    required this.bpm,
    required this.spo2,
    required this.temperature,
    required this.isDanger,
  });
}

/// Logged Clinical Event
class ClinicalEvent {
  final DateTime timestamp;
  final String title;
  final String description;
  final bool isHazard;

  ClinicalEvent({
    required this.timestamp,
    required this.title,
    required this.description,
    required this.isHazard,
  });
}

/// Clinical Thresholds Profile
class VitalsThresholds {
  int minBpm;
  int maxBpm;
  int minSpo2;
  double minTemp;
  double maxTemp;

  VitalsThresholds({
    this.minBpm = 60,
    this.maxBpm = 100,
    this.minSpo2 = 95,
    this.minTemp = 36.1,
    this.maxTemp = 37.5,
  });
}

/// Model representation of the data at `/patient`
class PatientVitals {
  final int bpm;
  final int spo2;
  final double temperature;
  final bool isDanger;
  final String status;
  final String patientId;
  final String patientName;
  final DateTime lastUpdated;

  PatientVitals({
    required this.bpm,
    required this.spo2,
    required this.temperature,
    required this.isDanger,
    required this.status,
    required this.patientId,
    required this.patientName,
    required this.lastUpdated,
  });

  factory PatientVitals.initial(PatientBed bed) {
    return PatientVitals(
      bpm: 76,
      spo2: 98,
      temperature: 36.8,
      isDanger: false,
      status: 'Normal',
      patientId: bed.id,
      patientName: bed.patientName,
      lastUpdated: DateTime.now(),
    );
  }

  factory PatientVitals.fromMap(
    Map<dynamic, dynamic> map,
    PatientBed bed,
    VitalsThresholds thresholds,
  ) {
    int parseSafeInt(dynamic val, int fallback) {
      if (val is int) return val;
      if (val is double) return val.toInt();
      if (val is String) return int.tryParse(val) ?? fallback;
      return fallback;
    }

    double parseSafeDouble(dynamic val, double fallback) {
      if (val is double) return val;
      if (val is int) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? fallback;
      return fallback;
    }

    bool parseSafeBool(dynamic val, bool fallback) {
      if (val is bool) return val;
      if (val is String) return val.toLowerCase() == 'true' || val == '1';
      if (val is int) return val == 1;
      return fallback;
    }

    final rawBpm = parseSafeInt(map['bpm'] ?? map['heartRate'] ?? map['BPM'], 75);
    final rawSpo2 = parseSafeInt(map['spo2'] ?? map['spO2'] ?? map['SpO2'], 98);
    final rawTemp = parseSafeDouble(map['temp'] ?? map['temperature'] ?? map['Temp'], 36.8);

    final autoDanger = (rawBpm < thresholds.minBpm || rawBpm > thresholds.maxBpm) ||
        (rawSpo2 < thresholds.minSpo2) ||
        (rawTemp > thresholds.maxTemp || rawTemp < thresholds.minTemp);
    final explicitDanger = parseSafeBool(map['isDanger'] ?? map['danger'], false);

    return PatientVitals(
      bpm: rawBpm,
      spo2: rawSpo2,
      temperature: rawTemp,
      isDanger: explicitDanger || autoDanger,
      status: (map['status'] ?? (explicitDanger || autoDanger ? 'Critical' : 'Normal')).toString(),
      patientId: (map['patientId'] ?? map['id'] ?? bed.id).toString(),
      patientName: (map['patientName'] ?? map['name'] ?? bed.patientName).toString(),
      lastUpdated: DateTime.now(),
    );
  }
}

/// Main Monitoring Dashboard Screen
class PatientMonitorScreen extends StatefulWidget {
  final bool initialFirebaseStatus;

  const PatientMonitorScreen({super.key, required this.initialFirebaseStatus});

  @override
  State<PatientMonitorScreen> createState() => _PatientMonitorScreenState();
}

class _PatientMonitorScreenState extends State<PatientMonitorScreen>
    with SingleTickerProviderStateMixin {
  // Available Hospital Beds
  final List<PatientBed> _beds = const [
    PatientBed(
      id: 'PT-9042',
      bedNumber: 'Bed 01',
      patientName: 'Eleanor Vance',
      department: 'ICU-A',
      firebasePath: 'patient',
    ),
    PatientBed(
      id: 'PT-9043',
      bedNumber: 'Bed 02',
      patientName: 'Marcus Sterling',
      department: 'Cardiology',
      firebasePath: 'patients/bed2',
    ),
    PatientBed(
      id: 'PT-9044',
      bedNumber: 'Bed 03',
      patientName: 'Sophia Chen',
      department: 'Trauma Unit',
      firebasePath: 'patients/bed3',
    ),
    PatientBed(
      id: 'PT-9045',
      bedNumber: 'Bed 04',
      patientName: 'David Kim',
      department: 'CCU Recovery',
      firebasePath: 'patients/bed4',
    ),
  ];

  late PatientBed _selectedBed;
  late PatientVitals _vitals;
  final VitalsThresholds _thresholds = VitalsThresholds();

  // State Management
  bool _isConnected = false;
  bool _isDemoMode = false;
  bool _useFahrenheit = false;
  bool _isAlarmMuted = false;
  String _selectedChartMetric = 'BPM'; // 'BPM', 'SpO2', 'Temp'

  // History & Event Logs
  final List<VitalHistoryPoint> _historyPoints = [];
  final List<ClinicalEvent> _eventLogs = [];

  StreamSubscription<DatabaseEvent>? _dbSubscription;
  Timer? _demoTimer;
  Timer? _alarmAudioTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _selectedBed = _beds.first;
    _vitals = PatientVitals.initial(_selectedBed);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Initial mock history seed
    _seedInitialHistory();

    if (widget.initialFirebaseStatus) {
      _listenToFirebase();
    } else {
      _isDemoMode = true;
      _startDemoSimulation();
    }

    _startAlarmAudioLoop();
  }

  @override
  void dispose() {
    _dbSubscription?.cancel();
    _demoTimer?.cancel();
    _alarmAudioTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _seedInitialHistory() {
    final now = DateTime.now();
    for (int i = 15; i >= 0; i--) {
      _historyPoints.add(VitalHistoryPoint(
        timestamp: now.subtract(Duration(seconds: i * 4)),
        bpm: 72 + (i % 6),
        spo2: 97 + (i % 3),
        temperature: 36.6 + ((i % 4) * 0.1),
        isDanger: false,
      ));
    }
    _eventLogs.add(ClinicalEvent(
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      title: 'Telemetry Session Initialized',
      description: 'Connected to ICU monitoring network.',
      isHazard: false,
    ));
  }

  /// Audible & Haptic Alarm Loop
  void _startAlarmAudioLoop() {
    _alarmAudioTimer?.cancel();
    _alarmAudioTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) return;
      if (_vitals.isDanger && !_isAlarmMuted) {
        // Play system audio chime and trigger medical alert haptic pulse
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
      }
    });
  }

  /// Listens to real-time changes at the Firebase Database reference
  void _listenToFirebase() {
    _dbSubscription?.cancel();
    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref(_selectedBed.firebasePath);

      _dbSubscription = ref.onValue.listen((DatabaseEvent event) {
        if (!mounted) return;
        final data = event.snapshot.value;
        if (data != null && data is Map) {
          final newVitals = PatientVitals.fromMap(data, _selectedBed, _thresholds);
          _onNewTelemetryReceived(newVitals);
          setState(() {
            _isConnected = true;
          });
        }
      }, onError: (error) {
        debugPrint('Firebase Realtime Database Error: $error');
        if (mounted) {
          setState(() {
            _isConnected = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Error attaching Firebase listener: $e');
      setState(() {
        _isConnected = false;
      });
    }
  }

  void _onNewTelemetryReceived(PatientVitals newVitals) {
    final wasDanger = _vitals.isDanger;
    setState(() {
      _vitals = newVitals;
      _historyPoints.add(VitalHistoryPoint(
        timestamp: newVitals.lastUpdated,
        bpm: newVitals.bpm,
        spo2: newVitals.spo2,
        temperature: newVitals.temperature,
        isDanger: newVitals.isDanger,
      ));
      if (_historyPoints.length > 25) {
        _historyPoints.removeAt(0);
      }

      // Record Clinical Event if state transitions to danger
      if (newVitals.isDanger && !wasDanger) {
        _eventLogs.insert(
          0,
          ClinicalEvent(
            timestamp: DateTime.now(),
            title: 'Critical Alarm Triggered',
            description: '${newVitals.status} (HR: ${newVitals.bpm}, SpO2: ${newVitals.spo2}%)',
            isHazard: true,
          ),
        );
      } else if (!newVitals.isDanger && wasDanger) {
        _eventLogs.insert(
          0,
          ClinicalEvent(
            timestamp: DateTime.now(),
            title: 'Vitals Normalized',
            description: 'Patient parameters returned to safe threshold.',
            isHazard: false,
          ),
        );
      }
    });
  }

  /// Simulated stream for testing vitals and danger state transitions
  void _startDemoSimulation() {
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isDemoMode || !mounted) return;

      final random = math.Random();
      PatientVitals simVitals;

      if (_vitals.isDanger) {
        simVitals = PatientVitals(
          bpm: 135 + random.nextInt(10),
          spo2: 89 - random.nextInt(3),
          temperature: 39.2 + (random.nextDouble() * 0.4),
          isDanger: true,
          status: 'CRITICAL TACHYCARDIA & HYPOXIA',
          patientId: _selectedBed.id,
          patientName: _selectedBed.patientName,
          lastUpdated: DateTime.now(),
        );
      } else {
        final newBpm = 72 + random.nextInt(8);
        final newSpo2 = 97 + random.nextInt(3);
        final newTemp = 36.6 + (random.nextDouble() * 0.4);
        simVitals = PatientVitals(
          bpm: newBpm,
          spo2: newSpo2,
          temperature: double.parse(newTemp.toStringAsFixed(1)),
          isDanger: false,
          status: 'Normal',
          patientId: _selectedBed.id,
          patientName: _selectedBed.patientName,
          lastUpdated: DateTime.now(),
        );
      }

      _onNewTelemetryReceived(simVitals);
    });
  }

  void _toggleDangerState() {
    final willBeDanger = !_vitals.isDanger;
    final toggled = PatientVitals(
      bpm: willBeDanger ? 138 : 74,
      spo2: willBeDanger ? 88 : 98,
      temperature: willBeDanger ? 39.4 : 36.7,
      isDanger: willBeDanger,
      status: willBeDanger ? 'HIGH HYPOXIA & FEVER' : 'Normal',
      patientId: _selectedBed.id,
      patientName: _selectedBed.patientName,
      lastUpdated: DateTime.now(),
    );
    _onNewTelemetryReceived(toggled);
  }

  void _switchBed(PatientBed bed) {
    if (_selectedBed.id == bed.id) return;
    setState(() {
      _selectedBed = bed;
      _vitals = PatientVitals.initial(bed);
      _historyPoints.clear();
      _seedInitialHistory();
      if (!_isDemoMode && widget.initialFirebaseStatus) {
        _listenToFirebase();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final double displayTemp = _useFahrenheit
        ? (_vitals.temperature * 9 / 5) + 32
        : _vitals.temperature;
    final String tempUnit = _useFahrenheit ? '°F' : '°C';

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1322),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.monitor_heart, color: Color(0xFF00E5FF), size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ICU TELEMETRY',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Node: /${_selectedBed.firebasePath}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.5),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Alarm Mute Toggle Button
          IconButton(
            tooltip: _isAlarmMuted ? 'Alarm Muted' : 'Audible Alarm Active',
            icon: Icon(
              _isAlarmMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _isAlarmMuted ? const Color(0xFFFFB300) : const Color(0xFF00E5FF),
            ),
            onPressed: () {
              setState(() {
                _isAlarmMuted = !_isAlarmMuted;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  backgroundColor: const Color(0xFF131A29),
                  content: Text(
                    _isAlarmMuted
                        ? '🔇 Audible alarm muted.'
                        : '🔔 Audible alarm unmuted & armed.',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),

          // Temperature Unit Toggle
          IconButton(
            tooltip: 'Switch °C / °F',
            icon: Icon(
              _useFahrenheit ? Icons.thermostat : Icons.device_thermostat,
              color: Colors.white70,
            ),
            onPressed: () {
              setState(() {
                _useFahrenheit = !_useFahrenheit;
              });
            },
          ),

          // Thresholds Config Button
          IconButton(
            tooltip: 'Configure Thresholds',
            icon: const Icon(Icons.tune_rounded, color: Colors.white70),
            onPressed: _showThresholdConfigSheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Multi-Bed Hospital Ward Selector
            _buildMultiBedSelector(),
            const SizedBox(height: 14),

            // Patient Identification Header Card
            _buildPatientHeader(),
            const SizedBox(height: 14),

            // Alert Banner (Emergency Pulsing or Stable)
            _buildAlertBanner(),
            const SizedBox(height: 16),

            // Real-time Waveform Monitor (ECG)
            _buildEcWaveformCard(),
            const SizedBox(height: 16),

            // Telemetry Cards Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PHYSIOLOGICAL VITALS',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'Updated: ${_formatTime(_vitals.lastUpdated)}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Vitals Cards
            _buildBpmCard(),
            const SizedBox(height: 12),
            _buildSpo2Card(),
            const SizedBox(height: 12),
            _buildTempCard(displayTemp, tempUnit),
            const SizedBox(height: 18),

            // Historical Trend Chart & Analytics
            _buildHistoryTrendsSection(),
            const SizedBox(height: 18),

            // Incident Event Log & Actions
            _buildEventLogSection(),
            const SizedBox(height: 18),

            // Simulation & Test Controller
            _buildTestingControlSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// Multi-Bed Ward Selector
  Widget _buildMultiBedSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SELECT BED / WARD MONITOR',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _beds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final bed = _beds[index];
              final isSelected = bed.id == _selectedBed.id;

              return InkWell(
                onTap: () => _switchBed(bed),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.15) : const Color(0xFF111726),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF1E293B),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? (_vitals.isDanger ? const Color(0xFFFF1744) : const Color(0xFF10B981))
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${bed.bedNumber} • ${bed.patientName.split(" ").first}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Patient Bio Header Card
  Widget _buildPatientHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF00E5FF).withOpacity(0.12),
            child: const Icon(Icons.person, color: Color(0xFF00E5FF), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _selectedBed.patientName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _selectedBed.id,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${_selectedBed.bedNumber} • ${_selectedBed.department}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          // Connection Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (_isConnected || _isDemoMode)
                  ? const Color(0xFF10B981).withOpacity(0.15)
                  : const Color(0xFFEF4444).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (_isConnected || _isDemoMode)
                    ? const Color(0xFF10B981).withOpacity(0.5)
                    : const Color(0xFFEF4444).withOpacity(0.5),
              ),
            ),
            child: Text(
              _isDemoMode ? 'SIMULATOR' : (_isConnected ? 'LIVE SYNC' : 'OFFLINE'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: (_isConnected || _isDemoMode)
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Alert Banner
  Widget _buildAlertBanner() {
    final bool isHazard = _vitals.isDanger;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: isHazard
              ? [const Color(0xFF881337), const Color(0xFF991B1B)]
              : [const Color(0xFF064E3B), const Color(0xFF065F46)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isHazard ? const Color(0xFFFF3366) : const Color(0xFF10B981),
          width: isHazard ? 2 : 1,
        ),
        boxShadow: isHazard
            ? [
                BoxShadow(
                  color: const Color(0xFFFF1744).withOpacity(0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHazard ? Icons.warning_rounded : Icons.verified_user_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isHazard ? 'CRITICAL PHYSIOLOGICAL ALERT' : 'PATIENT VITALS NORMAL',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (isHazard && _isAlarmMuted)
                      const Text(
                        'MUTED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFFE082),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isHazard
                      ? 'Condition: ${_vitals.status}. Threshold breach detected. Immediate clinical review advised.'
                      : 'All physiological parameters are safe within calibrated thresholds.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Live Waveform Display
  Widget _buildEcWaveformCard() {
    return Container(
      height: 95,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.show_chart, color: Color(0xFF00E5FF), size: 15),
                  SizedBox(width: 6),
                  Text(
                    'ECG PLETHYSMOGRAM',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              Text(
                '${_vitals.bpm} BPM Live Sync',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: EcWaveformPainter(
                    progress: _pulseController.value,
                    isDanger: _vitals.isDanger,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Heart Rate Card
  Widget _buildBpmCard() {
    final bool isBpmAbnormal =
        _vitals.bpm < _thresholds.minBpm || _vitals.bpm > _thresholds.maxBpm;
    const color = Color(0xFFFF3366);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isBpmAbnormal ? color.withOpacity(0.8) : const Color(0xFF1E293B),
          width: isBpmAbnormal ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = 1.0 + (_pulseController.value * 0.2);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.favorite, color: color, size: 18),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HEART RATE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Pulse Frequency',
                        style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ],
              ),
              _buildRangeTag(
                '${_thresholds.minBpm} - ${_thresholds.maxBpm} BPM',
                isBpmAbnormal,
                color,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${_vitals.bpm}',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'BPM',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                _vitals.bpm > _thresholds.maxBpm
                    ? 'Tachycardia'
                    : (_vitals.bpm < _thresholds.minBpm ? 'Bradycardia' : 'Normal Sinus'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isBpmAbnormal ? color : const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Blood Oxygen Card
  Widget _buildSpo2Card() {
    final bool isSpo2Abnormal = _vitals.spo2 < _thresholds.minSpo2;
    const color = Color(0xFF00E5FF);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSpo2Abnormal ? const Color(0xFFFF5252) : const Color(0xFF1E293B),
          width: isSpo2Abnormal ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.water_drop_rounded, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BLOOD OXYGEN',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Oxygen Saturation (SpO2)',
                        style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ],
              ),
              _buildRangeTag(
                '≥ ${_thresholds.minSpo2}% Target',
                isSpo2Abnormal,
                const Color(0xFFFF5252),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${_vitals.spo2}',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '%',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                _vitals.spo2 < 90
                    ? 'Critical Hypoxia'
                    : (_vitals.spo2 < _thresholds.minSpo2 ? 'Mild Hypoxemia' : 'Optimal Perfusion'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSpo2Abnormal ? const Color(0xFFFF5252) : const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_vitals.spo2 / 100).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: AlwaysStoppedAnimation<Color>(
                isSpo2Abnormal ? const Color(0xFFFF5252) : color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Temperature Card
  Widget _buildTempCard(double displayTemp, String unit) {
    final bool isTempAbnormal =
        _vitals.temperature > _thresholds.maxTemp || _vitals.temperature < _thresholds.minTemp;
    const color = Color(0xFFFFB300);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTempAbnormal ? color.withOpacity(0.8) : const Color(0xFF1E293B),
          width: isTempAbnormal ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.thermostat_rounded, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BODY TEMPERATURE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Core Thermal Sensor',
                        style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ],
              ),
              _buildRangeTag(
                _useFahrenheit ? '97.0 - 99.5°F' : '${_thresholds.minTemp} - ${_thresholds.maxTemp}°C',
                isTempAbnormal,
                color,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                displayTemp.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                _vitals.temperature > 38.0
                    ? 'Pyrexia / Fever'
                    : (_vitals.temperature < 35.5 ? 'Hypothermia' : 'Normothermic'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isTempAbnormal ? color : const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Historical Vital Trend Section & Smooth Chart
  Widget _buildHistoryTrendsSection() {
    // Calculate statistics for the current metric
    double currentVal = 0;
    double minVal = 999;
    double maxVal = -999;
    double sum = 0;

    for (final p in _historyPoints) {
      double v = 0;
      if (_selectedChartMetric == 'BPM') {
        v = p.bpm.toDouble();
      } else if (_selectedChartMetric == 'SpO2') {
        v = p.spo2.toDouble();
      } else {
        v = _useFahrenheit ? (p.temperature * 9 / 5) + 32 : p.temperature;
      }
      currentVal = v;
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
      sum += v;
    }
    final avgVal = _historyPoints.isNotEmpty ? sum / _historyPoints.length : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.timeline_rounded, color: Color(0xFF00E5FF), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'HISTORICAL TELEMETRY TREND',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              // Metric Pills Switcher
              Row(
                children: ['BPM', 'SpO2', 'Temp'].map((metric) {
                  final isSel = _selectedChartMetric == metric;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedChartMetric = metric;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF00E5FF).withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSel ? const Color(0xFF00E5FF) : const Color(0xFF1E293B),
                        ),
                      ),
                      child: Text(
                        metric,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSel ? const Color(0xFF00E5FF) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Statistics Summary Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip('CURRENT', currentVal.toStringAsFixed(1)),
              _buildStatChip('MIN', minVal == 999 ? '--' : minVal.toStringAsFixed(1)),
              _buildStatChip('AVG', avgVal.toStringAsFixed(1)),
              _buildStatChip('MAX', maxVal == -999 ? '--' : maxVal.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 14),

          // Custom Painted Chart
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size.infinite,
              painter: TelemetryTrendChartPainter(
                points: _historyPoints,
                metric: _selectedChartMetric,
                useFahrenheit: _useFahrenheit,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// Incident Event Logs & Emergency Actions
  Widget _buildEventLogSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded, color: Color(0xFF00E5FF), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'CLINICAL INCIDENT LOG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Text(
                '${_eventLogs.length} Events',
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Scrollable event list
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _eventLogs.length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E293B), height: 12),
              itemBuilder: (context, index) {
                final ev = _eventLogs[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ev.isHazard ? const Color(0xFFFF1744) : const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                ev.title,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: ev.isHazard ? const Color(0xFFFF5252) : Colors.white,
                                ),
                              ),
                              Text(
                                _formatTime(ev.timestamp),
                                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ev.description,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Quick Action Dispatch
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.call_rounded, size: 16),
                  label: const Text('Call Nurse Station', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('📞 Directing call to Central ICU Nurse Station...'),
                        backgroundColor: Color(0xFF0D1424),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1744),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.emergency_rounded, size: 16, color: Colors.white),
                  label: const Text('Code Blue Alert', style: TextStyle(fontSize: 11, color: Colors.white)),
                  onPressed: () {
                    _toggleDangerState();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🚨 Code Blue alert broadcast to crash cart team!'),
                        backgroundColor: Color(0xFF881337),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Simulation & Test Suite
  Widget _buildTestingControlSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1322),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.developer_mode_rounded, color: Color(0xFF00E5FF), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'DEVELOPER TELEMETRY SIMULATOR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _isDemoMode,
                activeColor: const Color(0xFF00E5FF),
                onChanged: (val) {
                  setState(() {
                    _isDemoMode = val;
                    if (_isDemoMode) {
                      _startDemoSimulation();
                    } else {
                      _demoTimer?.cancel();
                      if (widget.initialFirebaseStatus) {
                        _listenToFirebase();
                      }
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Simulate physiological telemetry stream and test emergency alarms before physical sensors are broadcast.',
            style: TextStyle(fontSize: 10, color: Color(0xFF64748B), height: 1.3),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _vitals.isDanger
                  ? const Color(0xFF10B981)
                  : const Color(0xFFFF1744),
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(
              _vitals.isDanger ? Icons.check_circle : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 18,
            ),
            label: Text(
              _vitals.isDanger ? 'Reset Vitals to Stable' : 'Trigger Critical Hazard State',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
            ),
            onPressed: _toggleDangerState,
          ),
        ],
      ),
    );
  }

  /// Threshold Configuration Bottom Sheet
  void _showThresholdConfigSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CALIBRATE SAFE THRESHOLDS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Customize triggers for the dynamic alert banner and alarms.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  Text('Max Heart Rate: ${_thresholds.maxBpm} BPM', style: const TextStyle(fontSize: 12)),
                  Slider(
                    value: _thresholds.maxBpm.toDouble(),
                    min: 80,
                    max: 160,
                    divisions: 16,
                    activeColor: const Color(0xFFFF3366),
                    onChanged: (val) {
                      setSheetState(() => _thresholds.maxBpm = val.toInt());
                      setState(() {});
                    },
                  ),
                  Text('Min Blood Oxygen: ${_thresholds.minSpo2}%', style: const TextStyle(fontSize: 12)),
                  Slider(
                    value: _thresholds.minSpo2.toDouble(),
                    min: 85,
                    max: 98,
                    divisions: 13,
                    activeColor: const Color(0xFF00E5FF),
                    onChanged: (val) {
                      setSheetState(() => _thresholds.minSpo2 = val.toInt());
                      setState(() {});
                    },
                  ),
                  Text('Max Body Temperature: ${_thresholds.maxTemp.toStringAsFixed(1)}°C', style: const TextStyle(fontSize: 12)),
                  Slider(
                    value: _thresholds.maxTemp,
                    min: 37.0,
                    max: 40.0,
                    divisions: 30,
                    activeColor: const Color(0xFFFFB300),
                    onChanged: (val) {
                      setSheetState(() => _thresholds.maxTemp = double.parse(val.toStringAsFixed(1)));
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Save & Apply Thresholds', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRangeTag(String range, bool isAlert, Color alertColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isAlert ? alertColor.withOpacity(0.18) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAlert ? alertColor.withOpacity(0.6) : Colors.transparent,
        ),
      ),
      child: Text(
        range,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isAlert ? alertColor : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

/// Custom ECG Waveform Painter
class EcWaveformPainter extends CustomPainter {
  final double progress;
  final bool isDanger;

  EcWaveformPainter({required this.progress, required this.isDanger});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDanger ? const Color(0xFFFF3366) : const Color(0xFF00E5FF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final midY = size.height * 0.5;
    path.moveTo(0, midY);

    const pointsCount = 60;
    final stepX = size.width / pointsCount;

    for (int i = 0; i <= pointsCount; i++) {
      final x = i * stepX;
      final normalizedX = (i / pointsCount + progress) % 1.0;

      double yOffset = 0;
      if (normalizedX > 0.40 && normalizedX < 0.44) {
        yOffset = -size.height * 0.18;
      } else if (normalizedX >= 0.44 && normalizedX < 0.47) {
        yOffset = size.height * 0.12;
      } else if (normalizedX >= 0.47 && normalizedX < 0.52) {
        yOffset = -size.height * 0.45;
      } else if (normalizedX >= 0.52 && normalizedX < 0.56) {
        yOffset = size.height * 0.22;
      } else if (normalizedX >= 0.56 && normalizedX < 0.65) {
        yOffset = -size.height * 0.22;
      }

      if (i == 0) {
        path.moveTo(x, midY + yOffset);
      } else {
        path.lineTo(x, midY + yOffset);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant EcWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDanger != isDanger;
  }
}

/// Custom Historical Telemetry Trend Chart Painter
class TelemetryTrendChartPainter extends CustomPainter {
  final List<VitalHistoryPoint> points;
  final String metric;
  final bool useFahrenheit;

  TelemetryTrendChartPainter({
    required this.points,
    required this.metric,
    required this.useFahrenheit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    Color themeColor;
    double minY, maxY;

    if (metric == 'BPM') {
      themeColor = const Color(0xFFFF3366);
      minY = 40;
      maxY = 150;
    } else if (metric == 'SpO2') {
      themeColor = const Color(0xFF00E5FF);
      minY = 80;
      maxY = 100;
    } else {
      themeColor = const Color(0xFFFFB300);
      minY = useFahrenheit ? 95 : 35;
      maxY = useFahrenheit ? 104 : 40;
    }

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Line Path
    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (points.length - 1);

    for (int i = 0; i < points.length; i++) {
      double val = 0;
      if (metric == 'BPM') {
        val = points[i].bpm.toDouble();
      } else if (metric == 'SpO2') {
        val = points[i].spo2.toDouble();
      } else {
        val = useFahrenheit
            ? (points[i].temperature * 9 / 5) + 32
            : points[i].temperature;
      }

      final normalizedY = 1.0 - ((val - minY) / (maxY - minY)).clamp(0.0, 1.0);
      final x = i * stepX;
      final y = normalizedY * size.height;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      if (i == points.length - 1) {
        fillPath.lineTo(x, size.height);
        fillPath.close();
      }
    }

    // Fill Gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          themeColor.withOpacity(0.25),
          themeColor.withOpacity(0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..color = themeColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant TelemetryTrendChartPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.metric != metric ||
        oldDelegate.useFahrenheit != useFahrenheit;
  }
}
