import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_bar.dart';
import '../widgets/section_card.dart';
import 'dart:math';

// 1. IMPORT THE MODERN INTEROP LIBRARY
import 'dart:js_interop';

// 2. DEFINE THE JAVASCRIPT BINDINGS (Static mappings for Chrome APIs)
@JS('chrome')
external Chrome? get chrome;

@JS()
extension type Chrome(JSObject _) implements JSObject {
  external Runtime get runtime;
}

@JS()
extension type Runtime(JSObject _) implements JSObject {
  external void sendMessage(String extensionId, JSAny message, JSFunction callback);
}

// Map the expected response schema from your background.js script
@JS()
extension type ExtensionResponse(JSObject _) implements JSObject {
  external bool? get success;
  external String? get temp;
  external String? get error;
}

class ThermostatControllerPage extends StatefulWidget {
  const ThermostatControllerPage({super.key});

  @override
  State<ThermostatControllerPage> createState() =>
      _ThermostatControllerPageState();
}

class _ThermostatControllerPageState extends State<ThermostatControllerPage> {
  final TextEditingController _serialController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();

  String _currentTemp = "";
  bool _isLoadingTemp = false;
  bool _isLoadingIdle = false; // New state for the Idle button

  // Your targeted Extension ID
  static const String extensionId = "olpajmliahjhlhdhcjmmeacgooefmomm";

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serialController.text = prefs.getString('saved_serial') ?? '';
      _ipController.text = prefs.getString('saved_ip') ?? '';
    });
  }

  Future<void> _fetchTemperatureAndSave() async {
    final serial = _serialController.text.trim();
    final ip = _ipController.text.trim();

    if (serial.isEmpty || ip.isEmpty) {
      setState(() {
        _currentTemp = "Please enter both fields.";
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_serial', serial);
    await prefs.setString('saved_ip', ip);

    setState(() {
      _isLoadingTemp = true;
      _currentTemp = "Routing request through Chrome Extension...";
    });

    final String timeId = DateTime.now().millisecondsSinceEpoch.toString();
    final String randomId = generateRandomString(6);
    final String customKey = '$timeId-$randomId';

    // Push data to Firebase Realtime Database
    try {
      final DatabaseReference dbRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://ecobee-csv-analyzer-default-rtdb.firebaseio.com/',
      ).ref('thermostat_lookups');

      await dbRef.child(customKey).set({
        'serialNumber': serial,
        'ipAddress': ip,
      });
    } catch (e) {
      debugPrint("Firebase push error: $e");
    }

    // .jsify() converts a Dart Map seamlessly into a native JavaScript Object
    final jsMessage = {
      "action": "fetchTemp",
      "ip": ip
    }.jsify();

    if (chrome == null) {
      setState(() {
        _isLoadingTemp = false;
        _currentTemp = "Bridge failed. Are you using a compatible Chromium browser?";
      });
      return;
    }

    try {
      chrome!.runtime.sendMessage(
        extensionId,
        jsMessage!,
            (JSAny? response) {
          setState(() {
            _isLoadingTemp = false;
            if (response != null) {
              final res = response as ExtensionResponse;
              if (res.success == true) {
                _currentTemp = res.temp?.toString() ?? 'No data';
              } else {
                _currentTemp = "Extension Error: ${res.error ?? 'Unknown error'}";
              }
            } else {
              _currentTemp = "Extension Error: No response from bridge.";
            }
          });
        }.toJS,
      );
    } catch (e) {
      setState(() {
        _isLoadingTemp = false;
        _currentTemp = "Failed to communicate with bridge layout.";
      });
      debugPrint("JS Interop invocation error: $e");
    }
  }

  // --- NEW FUNCTION: TRIGGER IDLE SCREEN ---
  Future<void> _triggerIdleScreen() async {
    final ip = _ipController.text.trim();

    if (ip.isEmpty) {
      setState(() => _currentTemp = "Please enter an IP address first.");
      return;
    }

    setState(() {
      _isLoadingIdle = true;
      _currentTemp = "Sending Idle Screen POST command...";
    });

    final jsMessage = {
      "action": "triggerIdleScreen",
      "ip": ip
    }.jsify();

    if (chrome == null) {
      setState(() {
        _isLoadingIdle = false;
        _currentTemp = "Bridge failed. Are you using a compatible Chromium browser?";
      });
      return;
    }

    try {
      chrome!.runtime.sendMessage(
        extensionId,
        jsMessage!,
            (JSAny? response) {
          setState(() {
            _isLoadingIdle = false;
            if (response != null) {
              final res = response as ExtensionResponse;
              if (res.success == true) {
                _currentTemp = "Success: Thermostat set to Idle Screen.";
              } else {
                _currentTemp = "Extension Error: ${res.error ?? 'Unknown error'}";
              }
            } else {
              _currentTemp = "Extension Error: No response from bridge.";
            }
          });
        }.toJS,
      );
    } catch (e) {
      setState(() {
        _isLoadingIdle = false;
        _currentTemp = "Failed to communicate with bridge layout.";
      });
      debugPrint("JS Interop invocation error: $e");
    }
  }

  @override
  void dispose() {
    _serialController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: const ConsistentAppBar(currentPage: "controller"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SectionCard(
              title: "Thermostat Controller1",
              children: [
                const Text(
                  "- For faster and more efficient troubleshooting, this screen allows users to enable features such as Adjust Temperature for Humidity, enable the active idle screen, navigate back to the home screen, and access additional troubleshooting tools.\n- Please note that this screen is intended for ecobee employees only. I will set up a sign up sheet for employees to enroll their thermostat and use this feature. \n- Please note that this feature is not available at the moment. Please check back again soon.",
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 24),

                TextField(
                  controller: _serialController,
                  decoration: const InputDecoration(
                    labelText: "Serial Number",
                    hintText: "e.g., 312345678901",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.qr_code),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: "IP Address",
                    hintText: "e.g., 192.168.1.100",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.wifi),
                  ),
                ),
                const SizedBox(height: 32),

                // Updated to a Wrap to comfortably fit both buttons and the response text
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLoadingTemp || _isLoadingIdle ? null : _fetchTemperatureAndSave,
                      icon: _isLoadingTemp
                          ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.thermostat),
                      label: const Text("Get Current Temperature"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),

                    ElevatedButton.icon(
                      onPressed: _isLoadingTemp || _isLoadingIdle ? null : _triggerIdleScreen,
                      icon: _isLoadingIdle
                          ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.screen_lock_portrait),
                      label: const Text("Idle Screen"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        backgroundColor: Colors.teal.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),

                    Text(
                      _currentTemp,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _currentTemp.contains("Error") ||
                            _currentTemp.contains("failed") ||
                            _currentTemp.contains("Failed")
                            ? Colors.red
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String generateRandomString(int length) {
  const chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  final Random rnd = Random();
  return String.fromCharCodes(Iterable.generate(
      length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
}