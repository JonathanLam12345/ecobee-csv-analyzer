import 'dart:convert';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:csv/csv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_database/firebase_database.dart';
/*
I would like to check if the thermostat ever rebooted. A black row starting from row #7 indicates the thermostat has no power.
if two or more consuective rows are blank, it's still con
*/

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize package info to get the version
  final info = await PackageInfo.fromPlatform();
  final String appVersion = info.version;

  // Pre-load the Material Icons font to prevent missing icons on first load
  final fontLoader = FontLoader('MaterialIcons');
  await fontLoader.load();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyA9faf7iTLDrH9MHlqr7Ro6SjvSOhMYGlg",
      authDomain: "ecobee-csv-analyzer.firebaseapp.com",
      projectId: "ecobee-csv-analyzer",
      storageBucket: "ecobee-csv-analyzer.firebasestorage.app",
      messagingSenderId: "296794280928",
      appId: "1:296794280928:web:c38d5cf609cbfeb56e5185",
      measurementId: "G-9VLF1JLCVW",
    ),
  );
  runApp(
    MaterialApp(
      title: "ecobee CSV Analyzer",
      home: ExcelProcessorApp(version: appVersion),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class ExcelProcessorApp extends StatefulWidget {
  final String version; // Add this line
  const ExcelProcessorApp({
    super.key,
    required this.version,
  }); // Add version here

  @override
  State<ExcelProcessorApp> createState() => _ExcelProcessorAppState();
}

class _ExcelProcessorAppState extends State<ExcelProcessorApp> {
  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  bool _isDragging = false;
  bool _isProcessing = false;
  String _statusMessage = "Drag & Drop CSV Here \nor\n Click to Upload";
  double? _totalFanHours; // New variable to store total fan hours
  String? _serialNumber;

  String? _latestVersion;
  late DatabaseReference _versionRef;

  @override
  void initState() {
    super.initState();
    // Initialize the reference to your specific database URL and 'version' key
    _versionRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://ecobee-csv-analyzer-default-rtdb.firebaseio.com/',
    ).ref('version');

    // Listen to changes in real-time
    _versionRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;
      if (data != null && mounted) {
        setState(() {
          _latestVersion = data.toString();
        });
      }
    });
  }

  void _pickFile() {
    final html.FileUploadInputElement uploadInput =
        html.FileUploadInputElement();
    uploadInput.accept = '.csv';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        analytics.logEvent(name: 'file_picked_manually');
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        reader.onLoadEnd.listen((e) async {
          final Uint8List bytes = reader.result as Uint8List;
          await _processFile(bytes, file.name);
        });
      }
    });
  }

  Future<void> _processFile(Uint8List bytes, String fileName) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Processing CSV...";
    });
    await analytics.logEvent(name: 'process_file_start');

    await Future.delayed(const Duration(milliseconds: 100));
    xlsio.Workbook? workbook;

    try {
      final String content = utf8.decode(bytes, allowMalformed: true);
      final List<List<dynamic>> csvRows = const CsvToListConverter(
        shouldParseNumbers: false,
        fieldDelimiter: ',',
        eol: '\n',
        allowInvalid: true,
      ).convert(content);

      if (csvRows.isEmpty) throw Exception("File is empty");

      workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      int? fanSecIndex;
      double totalFanSeconds = 0;

      if (csvRows.isNotEmpty && csvRows[0].length >= 4) {
        _serialNumber = csvRows[0][3].toString();
      }

      List<int> columnsToSkip = [];
      if (csvRows.length >= 6) {
        List<dynamic> headerRow = csvRows[5];
        for (int j = 0; j < headerRow.length; j++) {
          String headerText = headerRow[j].toString().toLowerCase().trim();
          if (headerText.contains("wind speed (km/h)")) {
            columnsToSkip.add(j);
          }
          if (headerRow[j].toString().trim() == "Fan (sec)") {
            fanSecIndex = j;
            break;
          }
        }
      }

      // Sum values from the "Fan (sec)" column starting from data rows (index 6)
      if (fanSecIndex != null) {
        for (int i = 6; i < csvRows.length; i++) {
          if (fanSecIndex < csvRows[i].length) {
            final double? val = double.tryParse(
              csvRows[i][fanSecIndex].toString(),
            );
            if (val != null) totalFanSeconds += val;
          }
        }
      }
      // At the end of the successful processing, update the state
      setState(() {
        _totalFanHours = totalFanSeconds / 3600; // Convert seconds to hours
        _statusMessage = "Conversion Successful!";
      });

      int maxColumns = 0;
      double maxHeaderLength = 0;
      bool hasLongCalendarContent = false;

      for (int i = 0; i < csvRows.length; i++) {
        final List<dynamic> rowData = csvRows[i];
        int targetCol = 1;

        for (int j = 0; j < rowData.length; j++) {
          if (columnsToSkip.contains(j)) continue;
          final dynamic rawValue = rowData[j];
          final String cellText = rawValue?.toString() ?? "";

          if (i == 5) {
            String? hexColor;
            if (cellText.contains("Cool Set Temp")) {
              hexColor = '#496daf';
            } else if (cellText.contains("Heat Set Temp")) {
              hexColor = '#fe4949';
            } else if (cellText.contains("Current Temp") ||
                cellText.contains("Thermostat Temperature")) {
              hexColor = '#ffff00';
            }

            if (targetCol > 4) {
              final xlsio.Range headerRange = sheet.getRangeByIndex(
                1,
                targetCol,
                6,
                targetCol,
              );
              headerRange.merge();
              headerRange.setText(cellText);
              headerRange.cellStyle.rotation = 90;
              headerRange.cellStyle.vAlign = xlsio.VAlignType.bottom;
              headerRange.cellStyle.hAlign = xlsio.HAlignType.center;
              if (hexColor != null) headerRange.cellStyle.backColor = hexColor;

              double length = cellText.length.toDouble();
              if (length > maxHeaderLength) maxHeaderLength = length;
            } else {
              final cellRange = sheet.getRangeByIndex(i + 1, targetCol);
              cellRange.setText(cellText);
              if (hexColor != null) cellRange.cellStyle.backColor = hexColor;
            }
          } else if (i >= 6 || targetCol <= 4) {
            final cellRange = sheet.getRangeByIndex(i + 1, targetCol);
            if (i == 0 && j == 3) {
              cellRange.setText(cellText);
            } else {
              final double? numericValue = double.tryParse(cellText);

              if (numericValue != null) {
                cellRange.setNumber(numericValue);
                final String currentHeader =
                    sheet.getRangeByIndex(6, targetCol).getText()?.trim() ?? "";
                if (currentHeader == "Heat Stage 1 (sec)" && numericValue > 0) {
                  cellRange.cellStyle.backColor = '#ffe5e8';
                } else if (currentHeader == "Fan (sec)" && numericValue > 0) {
                  cellRange.cellStyle.backColor = '#c6e0b4';
                } else if (currentHeader == "Cool Stage 1 (sec)" &&
                    numericValue > 0) {
                  cellRange.cellStyle.backColor = '#cadff2';
                }
              } else {
                cellRange.setText(cellText);
              }

              if (numericValue != null) {
                cellRange.setNumber(numericValue);
              } else {
                cellRange.setText(cellText);
              }

              if (i >= 6) {
                if (targetCol == 3) {
                  //System Setting
                  if (cellText == "heat") {
                    cellRange.cellStyle.backColor = '#ffe699';
                    cellRange.cellStyle.fontColor = '#a51a18';
                  } else if (cellText == "off") {
                    cellRange.cellStyle.backColor = '#e6f1df';
                    cellRange.cellStyle.fontColor = '#a51a18';
                  } else if (cellText == "auto") {
                    cellRange.cellStyle.backColor = '#CBC3E3';
                  } else if (cellText == "cool") {
                    cellRange.cellStyle.backColor = '#8ea9db';
                  }
                } else if (targetCol == 4) {
                  //System Mode
                  if (cellText == "heatOff") {
                    cellRange.cellStyle.backColor = '#ffe8ea';
                  } else if (cellText == "heatStage1On") {
                    cellRange.cellStyle.backColor = '#ffe5e8';
                  } else if (cellText == "heatStage1Off") {
                    cellRange.cellStyle.backColor = '#ffe8eb';
                  } else if (cellText == "compressorHeatStage1On") {
                    cellRange.cellStyle.backColor = '#ffe5e8';
                  } else if (cellText == "compressorHeatStage1Off") {
                    //not sure if this exist
                    cellRange.cellStyle.backColor = '#ffe8eb';
                  } else if (cellText == "compressorHeatOff") {
                    cellRange.cellStyle.backColor = '#ffe8eb';
                  } else if (cellText == "compressorCoolStage1On") {
                    cellRange.cellStyle.backColor = '#cadff2';
                  } else if (cellText == "compressorCoolOff") {
                    cellRange.cellStyle.backColor = '#c0cfea';
                  }
                } else if (targetCol == 5) {
                  //Calendar Event
                  if (cellText.contains("smartHome")) {
                    cellRange.cellStyle.backColor = '#f7c8ab';
                  } else if (cellText.contains("smartAway")) {
                    cellRange.cellStyle.backColor = '#d3b5e9';
                  } else if (cellText.contains("hold")) {
                    cellRange.cellStyle.backColor = '#c0d5ab';
                  } else if (cellText.contains("auto")) {
                    cellRange.cellStyle.backColor = '#a4fef5';
                  } else if (cellText.contains("(SmartRecovery)")) {
                    cellRange.cellStyle.backColor = '#c6e0b4';
                  }
                  if (cellText.length > 4) hasLongCalendarContent = true;
                } else if (targetCol == 6) {
                  //Program Mode
                  if (cellText == "Sleep") {
                    cellRange.cellStyle.backColor = '#a9d08e';
                  } else if (cellText == "Away") {
                    cellRange.cellStyle.backColor = '#cdace6';
                  } else if (cellText == "Home") {
                    cellRange.cellStyle.backColor = '#bdd7ee';
                  }
                }
              }
            }
          }
          if (targetCol > maxColumns) maxColumns = targetCol;
          targetCol++;
        }
      }

      double calculatedHeight = (maxHeaderLength * 3.2).clamp(20.0, 120.0);
      sheet.setRowHeightInPixels(6, calculatedHeight);

      for (int col = 1; col <= maxColumns; col++) {
        sheet.autoFitColumn(col);
        final xlsio.Range colRange = sheet.getRangeByIndex(6, col);
        final String headerText = colRange.getText() ?? "";
        if (headerText.contains("Calendar Event") && hasLongCalendarContent) {
          double autoWidth = colRange.columnWidth;
          colRange.columnWidth = autoWidth / 2;
        }
      }
      sheet.getRangeByIndex(1, 4).cellStyle.backColor = '#ffff00';
      if (csvRows.length >= 7) sheet.getRangeByIndex(7, 1).freezePanes();

      final List<int> outBytes = workbook.saveAsStream();
      final blob = html.Blob([
        outBytes,
      ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);

      String baseName = fileName.replaceAll(
        RegExp(r'\.(csv|xlsx)$', caseSensitive: false),
        '',
      );
      String downloadName = "$baseName(new).xlsx";

      html.AnchorElement(href: url)
        ..setAttribute("download", downloadName)
        ..click();
      html.Url.revokeObjectUrl(url);

      await analytics.logEvent(name: 'process_file_success');
      setState(() => _statusMessage = "Conversion Successful!");
      await Future.delayed(const Duration(seconds: 3));
      setState(() {
        _statusMessage = "Drag & Drop CSV Here \nor\n Click to Upload";
        _isDragging = false;
        _isProcessing = false;
      });
    } catch (e) {
      await analytics.logEvent(
        name: 'process_file_error',
        parameters: {'file_name': fileName, 'error': e.toString()},
      );
      setState(() => _statusMessage = "Error: ${e.toString()}");
    } finally {
      workbook?.dispose();
      setState(() => _isProcessing = false);
    }
  }

  bool _isUpToDate(String local, String remote) {
    try {
      List<int> localParts = local
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      List<int> remoteParts = remote
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();

      int maxLength = localParts.length > remoteParts.length
          ? localParts.length
          : remoteParts.length;

      for (int i = 0; i < maxLength; i++) {
        int localSegment = i < localParts.length ? localParts[i] : 0;
        int remoteSegment = i < remoteParts.length ? remoteParts[i] : 0;

        if (localSegment > remoteSegment) return true; // Local is ahead
        if (localSegment < remoteSegment) return false; // Local is behind
      }
      return true; // Versions are equal
    } catch (e) {
      return local == remote; // Fallback to simple string check on error
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- NEW: Logic to determine the version display text and color ---
    String displayVersionText = "Version ${widget.version}";
    Color versionColor = Colors.blueGrey.shade300;
    FontWeight versionWeight = FontWeight.w400;

    if (_latestVersion != null) {
      bool upToDate = _isUpToDate(widget.version, _latestVersion!);
      if (upToDate) {
        displayVersionText = "Version ${widget.version} (latest)";
        versionColor = Colors.green.shade600;
        versionWeight = FontWeight.w400;
      } else {
        displayVersionText = "Version ${widget.version} (Requires an update)";
        versionColor = Colors.redAccent;
        versionWeight = FontWeight.w600;
      }
    }

    return Scaffold(
      appBar: _buildConsistentAppBar(context, "Home"),
      backgroundColor: const Color(0xFFF8F9FB),

      // ... (Rest of your SingleChildScrollView body)
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: SelectableText(
                      displayVersionText, // Uses the dynamic text
                      style: TextStyle(
                        color: versionColor, // Uses the dynamic color
                        fontSize: 12, // Slightly larger for better visibility
                        fontWeight:
                            versionWeight, // Bolder if an update is required
                      ),
                    ),
                  ),
                ),

                // ... (The rest of your existing body code continues here) ...
                _buildSectionCard(
                  title: "About CSV Analyzer",
                  children: [
                    Text(
                      "A web app designed to transform raw ecobee thermostat system monitoring data into a clear and readable report for faster and more accurate diagnostics.",
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropTarget(
                  onDragDone: (details) async {
                    if (details.files.isNotEmpty) {
                      final file = details.files.first;
                      analytics.logEvent(name: 'file_dropped');
                      final bytes = await file.readAsBytes();
                      await _processFile(bytes, file.name);
                    }
                  },
                  onDragEntered: (details) =>
                      setState(() => _isDragging = true),
                  onDragExited: (details) =>
                      setState(() => _isDragging = false),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _pickFile,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 300,
                        width: 600,
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? Colors.blue.withOpacity(0.05)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _isDragging
                                ? Colors.blueAccent
                                : Colors.blueGrey.shade200,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isProcessing)
                              const CircularProgressIndicator()
                            else
                              Icon(
                                Icons.upload_file_rounded,
                                size: 80,
                                color: _isDragging
                                    ? Colors.blueAccent
                                    : Colors.blueGrey[200],
                              ),
                            const SizedBox(height: 20),
                            Text(
                              _statusMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // --- NEW: Summary Section ---
                if (_totalFanHours != null || _serialNumber != null)
                  _buildSectionCard(
                    title: "System Runtime Summary",
                    children: [
                      if (_serialNumber != null)
                        _buildTip("Thermostat Serial Number: $_serialNumber"),
                      if (_totalFanHours != null)
                        _buildTip(
                          "Total Fan Runtime: ${_totalFanHours!.toStringAsFixed(2)} hours",
                        ),
                    ],
                  ),

                // ----------------------------
                const SizedBox(height: 32),
                Text(
                  "Developed by Jonathan Lam",
                  style: TextStyle(
                    color: Colors.blueGrey.shade400,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildSectionCard({
  required String title,
  required List<Widget> children,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
        const SizedBox(height: 15),
        ...children,
      ],
    ),
  );
}

Widget _buildTip(String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "• ",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.blueGrey.shade700,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

AppBar _buildConsistentAppBar(BuildContext context, String currentPage) {
  // Helper to build the stylized nav button with high-visibility UX
  Widget navButton(String label, String pageId, VoidCallback onPressed) {
    bool isActive = currentPage == pageId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TextButton(
        onPressed: isActive ? null : onPressed,
        style: TextButton.styleFrom(
          // Active state gets a subtle background capsule
          backgroundColor: isActive
              ? Colors.white.withOpacity(0.15)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                letterSpacing: 0.8,
                // Bold text for active page [cite: 138]
                fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
              ),
            ),
            // High-visibility highlight bar
            if (isActive)
              Container(
                margin: const EdgeInsets.only(top: 4),
                // FIXED: Used .only instead of .top
                height: 3,
                width: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  return AppBar(
    title: const Text(
      "",
      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
    ),
    backgroundColor: Colors.blue,
    // Primary blue color [cite: 134]
    foregroundColor: Colors.white,
    // White text/icons [cite: 134]
    elevation: 4,
    automaticallyImplyLeading: false,

    // Removes the back arrow [cite: 134]

    // Everything in actions is right-aligned by default

    // ... inside _buildConsistentAppBar actions list ...
    actions: [
      navButton("HOME", "Home", () {
        // Check if we are currently on the Info page
        if (currentPage == "Info") {
          // Simply pop the current page to reveal the Home page underneath
          // This preserves all the state/data on the Home screen
          Navigator.pop(context);
        }
      }),
      navButton("How To Use", "Info", () {
        // Navigates to Info page with NO animation
        // The Home page stays alive in the background
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, anim1, anim2) => const HowToUsePage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      }),
      navButton("Privacy Policy", "privacy", () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, anim1, anim2) => const PrivacyPolicyPage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      }),
      const SizedBox(width: 12),
    ],
  );
}

class HowToUsePage extends StatelessWidget {
  const HowToUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: _buildConsistentAppBar(context, "Info"),
      // Added SingleChildScrollView and Padding to match the main page layout
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            // Constraints force the card to stay 900px wide, making the border visible
            constraints: const BoxConstraints(maxWidth: 900),
            child: _buildSectionCard(
              title: "User Tips & How to Use",
              children: [
                _buildTip(
                  "Upload your .csv Temperature Report by dragging it into the box above or clicking the box to browse the .csv file.",
                ),
                _buildTip(
                  "To locate your .csv file more easily, sort your folder by 'Date Modified' to see your most recent downloads first.",
                ),
                _buildTip(
                  "Please note the web app saves the report as a .xlsx file instead of a .csv file.\nTo have future .xlsx reports open automatically after processing, right-click the .xlsx file in Chrome's 'Recent Download History' and select 'Always open files of this type'.\nYou can also disable this setting for .csv files to prevent the unformatted data from opening automatically from AP2.",
                ),
                _buildTip(
                  "This web app is updated occasionally. To ensure you are using the latest version, you may need to clear your browser cache or at least for this webpage by pressing CTRL + F5 (Chrome for Windows).",
                ),
                _buildTip(
                  "Please reach out to Jonathan Lam on Slack to report any issues or to provide feedback.",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  Future<void> _launchGitHub() async {
    final Uri url = Uri.parse(
      'https://github.com/JonathanLam12345/ecobee-csv-analyzer',
    );

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: _buildConsistentAppBar(context, "privacy"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _buildSectionCard(
              title: "Privacy Policy",
              children: [
                const Text(
                  '''
This web app is built as a simple tool to help improve performance and make work easier for the team.

Information Collection:
We do not collect or store any personal information from users. Anything you use or enter on this website is not saved in a database or kept anywhere.

How the App Works:
For the CSV formatter feature, it reads thermostat reports, formats them according to requirements, and automatically saves the final file as an XLSX file onto the user's computer.

This web application is connected to a database only to:
- Retrieve the most up-to-date version number
- Make sure users are always using the latest version of the tool

Purpose of the Web App:
This website is only meant to be a work tool. It is designed to:
- Help improve productivity
- Support team workflows
- Make tasks easier and more efficient

Feedback:
Team members can give feedback or suggestions to improve the app.

Data Security:
No personal data is stored, so nothing is collected or shared.
                  ''',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  "GitHub Project:",
                ),

                const SizedBox(height: 6),

                GestureDetector(
                  onTap: _launchGitHub,
                  child: const Text(
                    'https://github.com/JonathanLam12345/ecobee-csv-analyzer',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

