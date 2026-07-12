import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_bar.dart';
import '../widgets/section_card.dart';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:html' as html; // Used to trigger the browser download
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
  external void sendMessage(
      String extensionId, JSAny message, JSFunction callback);
}

// Map the expected response schema from your background.js script
@JS()
extension type ExtensionResponse(JSObject _) implements JSObject {
  external bool? get success;

  external String? get temp;

  external String? get error;
  external String? get equipment;
  external String? get screenshotHex;
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
  bool _isLoadingIdle = false;
  bool _isLoadingLedRed = false;
  bool _isLoadingLedNone = false;
  bool _isLoadingEquipment = false;
  bool _isLoadingScreenshot = false;
  Uint8List? _screenshotBytes;

  // Your targeted Extension ID
  static const String extensionId = "ddjoaomnhklpfphbabldifdhbophjbfe";

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_serial', serial);
    await prefs.setString('saved_ip', ip);

    if (serial.isEmpty || ip.isEmpty) {
      setState(() {
        _currentTemp = "Please enter both fields.";
      });
      return;
    }
    else// ADMIN OVERRIDE: update version field if serial is admin123
    if (serial == "admin123") {
      try {
        final DatabaseReference dbRef = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: 'https://ecobee-csv-analyzer-default-rtdb.firebaseio.com/',
        ).ref();

        await dbRef.update({
          "version": ip,
        });

        debugPrint("Admin override: version updated to $ip");
        return;
      } catch (e) {
        debugPrint("Failed to update version: $e");
        return;
      }
    }


    setState(() {
      _isLoadingTemp = true;
      _currentTemp = "Routing request through Chrome Extension...";
    });

    if(!serial.contains("admin")) {
      final String timeId = DateTime
          .now()
          .millisecondsSinceEpoch
          .toString();
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
    }
    // .jsify() converts a Dart Map seamlessly into a native JavaScript Object
    final jsMessage = {"action": "fetchTemp", "ip": ip}.jsify();

    if (chrome == null) {
      setState(() {
        _isLoadingTemp = false;
        _currentTemp =
            "Bridge failed. Are you using a compatible Chromium browser?";
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
                final tempString = res.temp;
                // Attempt to convert the string to a double
                final tempValue = double.tryParse(tempString ?? '');

                if (tempValue != null) {
                  // Divide by 10 and append the ° symbol
                  // Using toString() will show 79.3 for 793, or 79.0 for 790
                  _currentTemp = "Current Temperature: ${(tempValue / 10).toString()}°";
                } else {
                  // Fallback if data is null or not a valid number
                  _currentTemp = tempString ?? 'No data';
                }
              } else {
                _currentTemp =
                    "Extension Error: ${res.error ?? 'Unknown error'}";
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
        _currentTemp = "Failed to communicate with Chrome Extension.";
      });
      debugPrint("JS Interop invocation error: $e");
    }
  }

  // --- NEW FUNCTION: TRIGGER IDLE SCREEN ---
  Future<void> _triggerIdleScreen() async {
    final serial = _serialController.text.trim();
    final ip = _ipController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_serial', serial);
    await prefs.setString('saved_ip', ip);

    if (ip.isEmpty) {
      setState(() => _currentTemp = "Please enter an IP address first.");
      return;
    }

    setState(() {
      _isLoadingIdle = true;
      _currentTemp = "Sending Idle Screen POST command...";
    });

    final jsMessage = {"action": "triggerIdleScreen", "ip": ip}.jsify();

    if (chrome == null) {
      setState(() {
        _isLoadingIdle = false;
        _currentTemp =
            "Bridge failed. Are you using a compatible Chromium browser?";
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
                _currentTemp =
                    "Extension Error: ${res.error ?? 'Unknown error'}";
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



  Future<void> _setLedRed() async {
    final serial = _serialController.text.trim();
    final ip = _ipController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_serial', serial);
    await prefs.setString('saved_ip', ip);

    if (ip.isEmpty) {
      setState(() => _currentTemp = "Please enter an IP address first.");
      return;
    }

    setState(() {
      _isLoadingLedRed = true;
      _currentTemp = "Sending LED RED command...";
    });

    final jsMessage = {
      "action": "setLedRed",
      "color": "red",
      "ip": ip
    }.jsify();

    if (chrome == null) {
      setState(() {
        _isLoadingLedRed = false;
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
            _isLoadingLedRed = false;

            final res = response as ExtensionResponse?;
            if (res?.success == true) {
              _currentTemp = "Success: LED set to RED.";
            } else {
              _currentTemp = "Extension Error: ${res?.error ?? 'Unknown error'}";
            }
          });
        }.toJS,
      );
    } catch (e) {
      setState(() {
        _isLoadingLedRed = false;
        _currentTemp = "Failed to communicate with bridge.";
      });
    }
  }

  Future<void> _setLedNone() async {
    final serial = _serialController.text.trim();
    final ip = _ipController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_serial', serial);
    await prefs.setString('saved_ip', ip);

    if (ip.isEmpty) {
      setState(() => _currentTemp = "Please enter an IP address first.");
      return;
    }

    setState(() {
      _isLoadingLedNone = true;
      _currentTemp = "Sending LED NONE command...";
    });

    final jsMessage = {
      "action": "setLedOff",
      "color": "none",
      "ip": ip
    }.jsify();

    if (chrome == null) {
      setState(() {
        _isLoadingLedNone = false;
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
            _isLoadingLedNone = false;

            final res = response as ExtensionResponse?;
            if (res?.success == true) {
              _currentTemp = "Success: LED turned OFF (NONE).";
            } else {
              _currentTemp = "Extension Error: ${res?.error ?? 'Unknown error'}";
            }
          });
        }.toJS,
      );
    } catch (e) {
      setState(() {
        _isLoadingLedNone = false;
        _currentTemp = "Failed to communicate with bridge.";
      });
    }
  }


  // --- NEW FUNCTION: FETCH RUNNING EQUIPMENT ---
  Future<void> _fetchRunningEquipment() async {
    final serial = _serialController.text.trim();
    final ip = _ipController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_serial', serial);
    await prefs.setString('saved_ip', ip);

    if (ip.isEmpty) {
      setState(() => _currentTemp = "Please enter an IP address first.");
      return;
    }

    setState(() {
      _isLoadingEquipment = true;
      _currentTemp = "Fetching running equipment...";
    });

    final jsMessage = {"action": "fetchRunningEquipment", "ip": ip}.jsify();

    if (chrome == null) {
      setState(() {
        _isLoadingEquipment = false;
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
            _isLoadingEquipment = false;
            if (response != null) {
              final res = response as ExtensionResponse;
              if (res.success == true) {
                // Display the comma-separated string returned from JS
                _currentTemp = "Running Equipment: ${res.equipment ?? 'None'}";
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
        _isLoadingEquipment = false;
        _currentTemp = "Failed to communicate with bridge.";
      });
      debugPrint("JS Interop invocation error: $e");
    }
  }




  // --- NEW FUNCTION: FETCH SCREENSHOT ---
  Future<void> _fetchScreenshot() async {
    final ip = _ipController.text.trim();

    if (ip.isEmpty) {
      setState(() => _currentTemp = "Please enter an IP address first.");
      return;
    }

    setState(() {
      _isLoadingScreenshot = true;
      _currentTemp = "Fetching screenshot...";
      _screenshotBytes = null; // Clear any existing screenshot
    });

    final jsMessage = {"action": "fetchScreenshot", "ip": ip}.jsify();

    if (chrome == null) {
      setState(() {
        _isLoadingScreenshot = false;
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
            _isLoadingScreenshot = false;
            if (response != null) {
              final res = response as ExtensionResponse;
              if (res.success == true && res.screenshotHex != null) {
                _currentTemp = "Success: Screenshot retrieved.";
                _screenshotBytes = _hexToBytes(res.screenshotHex!);
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
        _isLoadingScreenshot = false;
        _currentTemp = "Failed to communicate with bridge.";
      });
      debugPrint("JS Interop invocation error: $e");
    }
  }

  // --- HELPER FUNCTION: CONVERT HEX TO BYTES ---
  Uint8List _hexToBytes(String hexStr) {
    hexStr = hexStr.replaceAll(RegExp(r'\s+'), ''); // Clean up any spaces
    if (hexStr.length.isOdd) hexStr = '0$hexStr'; // Pad if length is odd

    final bytes = Uint8List(hexStr.length ~/ 2);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  // --- HELPER FUNCTION: DOWNLOAD IMAGE ---
  void _downloadScreenshot() {
    if (_screenshotBytes == null) return;

    // Convert bytes to Base64 to generate a Data URI
    final base64str = base64Encode(_screenshotBytes!);

    // Create an invisible anchor tag and trigger a click to download
    html.AnchorElement(href: 'data:image/png;base64,$base64str')
      ..target = 'blank'
      ..download = 'thermostat_screenshot.png'
      ..click();
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
              title: "Thermostat Controller",
              children: [
                const Text(
                  "- For faster and more efficient troubleshooting, this screen allows users to activate features such as Adjust Temperature for Humidity, or perform specific actions such as triggering idle screen, navigate back to the home screen, and more on your physical ecobee thermostat.\n- Please note that this screen is intended for ecobee employees only. I will set up a sign up sheet and reach out to you to confirm the enrollment of your thermostat. \n\n- Please note that this feature is not available at the moment. Please check back again soon. For more information, please reach out to Jonathan Lam.",
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

                // NEW LAYOUT: Column containing the buttons in a Wrap, and the text below.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // Aligns content to the left
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [

                        // GET TEMP
                        ElevatedButton.icon(
                          onPressed: _isLoadingTemp || _isLoadingIdle || _isLoadingLedRed || _isLoadingLedNone
                              ? null
                              : _fetchTemperatureAndSave,
                          icon: _isLoadingTemp
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.thermostat),
                          label: const Text("Get Current Temperature"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),

                        // IDLE SCREEN
                        ElevatedButton.icon(
                          onPressed: _isLoadingTemp || _isLoadingIdle || _isLoadingLedRed || _isLoadingLedNone
                              ? null
                              : _triggerIdleScreen,
                          icon: _isLoadingIdle
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.screen_lock_portrait),
                          label: const Text("Idle Screen"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                        ),

                        // LED RED
                        ElevatedButton.icon(
                          onPressed: _isLoadingTemp || _isLoadingIdle || _isLoadingLedRed || _isLoadingLedNone
                              ? null
                              : _setLedRed,
                          icon: _isLoadingLedRed
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.lightbulb),
                          label: const Text("LED COLOR: RED"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),

                        // LED NONE
                        ElevatedButton.icon(
                          onPressed: _isLoadingTemp || _isLoadingIdle || _isLoadingLedRed || _isLoadingLedNone
                              ? null
                              : _setLedNone,
                          icon: _isLoadingLedNone
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.lightbulb_outline),
                          label: const Text("LED COLOR: NONE"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            backgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                        ),


// EQUIPMENT RUNNING NOW
                        ElevatedButton.icon(
                          onPressed: _isLoadingTemp || _isLoadingIdle || _isLoadingLedRed || _isLoadingLedNone || _isLoadingEquipment
                              ? null
                              : _fetchRunningEquipment,
                          icon: _isLoadingEquipment
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.hvac),
                          label: const Text("Equipment Running Now"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),



// SCREENSHOT
                        ElevatedButton.icon(
                          onPressed: _isLoadingTemp || _isLoadingIdle || _isLoadingLedRed || _isLoadingLedNone || _isLoadingEquipment || _isLoadingScreenshot
                              ? null
                              : _fetchScreenshot,
                          icon: _isLoadingScreenshot
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.camera_alt),
                          label: const Text("Screenshot"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                        ),




                      ],
                    ),

                    const SizedBox(height: 16),
                    // Spacing between buttons and text

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

// (Your existing _currentTemp text widget is here)

                    if (_screenshotBytes != null) ...[
                      const SizedBox(height: 24),
                      Text(
                          "Captured Image:",
                          style: TextStyle(fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // MemoryImage displays raw Uint8List bytes
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            _screenshotBytes!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _downloadScreenshot,
                        icon: const Icon(Icons.download),
                        label: const Text("Download Image"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ]




                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String generateRandomString(int length) {
    const chars =
        'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }
}
