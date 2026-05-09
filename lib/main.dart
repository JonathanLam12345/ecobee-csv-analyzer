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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  double? _totalFanHours;
  String? _serialNumber;
  int? _rebootCount;
  List<String> _rebootDetails = [];

  String? _latestVersion;
  late DatabaseReference _versionRef;

  @override
  void initState() {
    super.initState();
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

      int rebootCounter = 0;
      bool inRebootPeriod = false;
      String rebootStartTimestamp = "";
      List<String> currentRebootDetails = [];
      String rebootStartDate = "";
      String rebootStartTime = "";

      // Start processing data from Row 7 (index 6)
      for (int i = 6; i < csvRows.length; i++) {
        List<dynamic> row = csvRows[i];

        // Skip rows that are too short to have Column K
        if (row.length < 11) continue;

        // Column C is index 2 | Column K is index 10
        String colC = row[2]?.toString().trim() ?? "";
        String colK = row[10]?.toString().trim() ?? "";

        // A REBOOT ROW: Column C is blank, but Column K HAS data
        bool isRebootRow = colC.isEmpty && colK.isNotEmpty;

        // AN ONLINE ROW: Column C has actual system data
        bool isOnline = colC.isNotEmpty;

        if (isRebootRow) {
          if (!inRebootPeriod) {
            // Grab the date and time when the power loss STARTS
            rebootStartDate = row[0]?.toString() ?? "";
            rebootStartTime = row[1]?.toString() ?? "";
          }
          // The thermostat has lost power/connection.
          // We DO NOT count it yet, we just mark that it went down.
          inRebootPeriod = true;
        } else if (isOnline) {
          // The thermostat is successfully reporting data.
          if (inRebootPeriod) {
            rebootCounter++;

            String detail =
                "Reboot #$rebootCounter|$rebootStartDate|$rebootStartTime";
            currentRebootDetails.add(detail);
            debugPrint(detail);
          }
          // Reset the flag so we can catch the next gap
          inRebootPeriod = false;
        }
      }
      // --------------------------------------

      // Update state at the end of processing
      setState(() {
        _rebootCount = rebootCounter;
        _rebootDetails = currentRebootDetails;
      });

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
                }
                else  if (currentHeader == "Heat Stage 2 (sec)" && numericValue > 0) {
                  cellRange.cellStyle.backColor = '#ffe5e8';
                }
                else if (currentHeader == "Aux Heat 1 (sec)" && numericValue > 0) {
                  cellRange.cellStyle.backColor = '#ffe5e8';
                }
               else  if (currentHeader == "Aux Heat 2 (sec)" && numericValue > 0) {
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
        displayVersionText = "Version ${widget.version} (Click to update)";
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
                    child: MouseRegion(
                      // The cursor will now correctly show the pointer/hand
                      cursor: (_latestVersion != null && !_isUpToDate(widget.version, _latestVersion!))
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      child: GestureDetector(
                        onTap: () {
                          if (_latestVersion != null && !_isUpToDate(widget.version, _latestVersion!)) {
                            html.window.location.reload();
                          }
                        },
                        child: Text( // Changed from SelectableText to Text
                          displayVersionText,
                          style: TextStyle(
                            color: versionColor,
                            fontSize: 12,
                            fontWeight: versionWeight,
                            decoration: (_latestVersion != null && !_isUpToDate(widget.version, _latestVersion!))
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),
                        ),
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

                if (_totalFanHours != null || _serialNumber != null)
                  _buildSectionCard(
                    maxWidth: 700,
                    title: "Thermostat Report Summary",
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_serialNumber != null)
                        Align(
                          alignment: Alignment.center,
                          child: FractionallySizedBox(
                            widthFactor: 0.60,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFF00),

                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: _buildTip(
                                "Thermostat Serial Number: $_serialNumber",
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      if (_totalFanHours != null)
                        Align(
                          alignment: Alignment.center,
                          child: FractionallySizedBox(
                            widthFactor: 0.60,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC6E0B4),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: _buildTip(
                                "Total Fan Runtime: ${_totalFanHours!.toStringAsFixed(2)} hours",
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      if (_rebootCount != null)
                        Column(
                          // Use a Column to stack the count and the details
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: FractionallySizedBox(
                                widthFactor: 0.60,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (_rebootCount! > 0)
                                        ? const Color(0xFFEF5350)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.black12),
                                  ),
                                  child: _buildTip(
                                    "Number of Thermostat Reboots: $_rebootCount",
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                            ..._rebootDetails.map(
                              (detail) => _buildTip(
                                detail,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),






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
  double? maxWidth,
  Color? backgroundColor,
  Color? borderColor,
  CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 24),
    constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: backgroundColor ?? Colors.white,
      // Defaults to white if no color provided
      borderRadius: BorderRadius.circular(12),
      border: borderColor != null
          ? Border.all(color: borderColor, width: 2)
          : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: SelectionArea(
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
      
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

Widget _buildTip(String text, {TextAlign textAlign = TextAlign.left}) {
  // 1. Define the colored bar style
  final TextStyle separatorStyle = const TextStyle(
    fontWeight: FontWeight.bold,
    color: Color(0xFFEF5350),
    fontSize: 15,
  );

  // 2. Define the normal text style
  final TextStyle normalStyle = TextStyle(
    color: Colors.black,
    fontSize: 12,
    height: 1.4,
  );

  // 3. NEW: Define the BOLD text style for your labels
  final TextStyle boldStyle = TextStyle(
    color: Colors.blueGrey.shade800, // Slightly darker to make the bold pop
    fontWeight: FontWeight.bold,     // Applies the bold weight
    fontSize: 12,
    height: 1.4,
  );

  // Logic to build the styled text
  Widget content;
  List<InlineSpan> spans = [];

  if (text.contains('|')) {
    List<String> parts = text.split('|');
    for (int i = 0; i < parts.length; i++) {

      // NEW: If it's the first part and contains "Reboot #", make it bold
      if (i == 0 && parts[i].trim().startsWith('Reboot #')) {
        spans.add(TextSpan(text: parts[i], style: boldStyle));
      } else {
        spans.add(TextSpan(text: parts[i], style: normalStyle));
      }

      // Add the bold colored separator if we aren't at the last part
      if (i < parts.length - 1) {
        spans.add(TextSpan(text: ' | ', style: separatorStyle));
      }
    }
  } else if (text.contains(':')) {
    // NEW: If the text has a colon, split it to make the label bold
    int colonIndex = text.indexOf(':');

    // Everything up to and including the colon becomes bold
    String boldPart = text.substring(0, colonIndex + 1);
    // Everything after the colon stays normal
    String normalPart = text.substring(colonIndex + 1);

    spans.add(TextSpan(text: boldPart, style: boldStyle));
    spans.add(TextSpan(text: normalPart, style: normalStyle));
  } else {
    // Fallback for regular lines without colons or bars
    spans.add(TextSpan(text: text, style: normalStyle));
  }

  // Compile the spans into the RichText widget
  content = RichText(
    textAlign: textAlign,
    text: TextSpan(children: spans),
  );

  // Handle Centered Layout
  if (textAlign == TextAlign.center) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Center(
        child: content,
      ),
    );
  }

  // Handle Default Left-Aligned Layout with Bullet
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "• ",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: content,
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

    foregroundColor: Colors.white,

    elevation: 4,
    automaticallyImplyLeading: false,

    actions: [
      navButton("HOME", "Home", () {
        if (currentPage != "Home") {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }),
      navButton("About", "Info", () {
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

      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Column(
            children: [
              ConstrainedBox(
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
                      "Please note the web app saves the report as a .xlsx file instead of a .csv file.\nTo have future .xlsx reports open automatically after processing, right-click the .xlsx file in Chrome's 'Recent Download History' and select 'Always open files of this type'.\nYou can also disable this setting for .csv files to prevent the unformatted data from opening automatically.",
                    ),
                    _buildTip(
                      "Please reach out to Jonathan Lam on Slack to report any issues or to provide feedback.",
                    ),
                  ],
                ),
              ),



              const SizedBox(height: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
                child: _buildSectionCard(
                  title: "Support this Project",
                  children: [
                    const Text(
                      "If you find this tool helpful for your diagnostics, please consider supporting its development. Maintaining this site takes time and comes with ongoing costs. Your support is greatly appreciated.",
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final url = Uri.parse("https://www.buymeacoffee.com/jonathanlam12345");
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFDD00), // BMC Yellow
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.coffee, size: 20),
                        label: const Text(
                          "Buy me a coffee",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              //
            ],
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
• We do not collect or store any personal information from users. Anything you use or enter on this website is not saved in a database or kept anywhere.
• Please note that an analytics counter is used to only track how many users have interacted with the application.

How the App Works:
• For the CSV formatter feature, it reads thermostat reports, formats them according to requirements, and automatically saves the final file as an XLSX file onto the user's computer.

This web application is connected to a database only to:
• Retrieve the most up-to-date version number to ensure users are always using the latest version of the tool

Purpose of the Web App:
This website is only meant to be a work tool. It is designed to:
• Help improve productivity
• Support team workflows
• Make tasks easier and more efficient

Feedback:
• Team members can give feedback or suggestions to improve the app.

Data Security:
• No personal data is stored. Once the application generates the output file and displays analyzed data on the screen, the application does not have access to any data anymore, therefore, nothing is collected or shared.
                  ''',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                ),

                // const SizedBox(height: 20),
                //
                // const Text("GitHub Project:"),
                //
                // const SizedBox(height: 6),
                //
                // GestureDetector(
                //   onTap: _launchGitHub,
                //   child: const Text(
                //     'https://github.com/JonathanLam12345/ecobee-csv-analyzer',
                //     style: TextStyle(
                //       fontSize: 14,
                //       color: Colors.blue,
                //       decoration: TextDecoration.underline,
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
