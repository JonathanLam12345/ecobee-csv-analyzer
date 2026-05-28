import 'dart:convert';
import 'dart:html' as html;

import 'package:csv/csv.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:ecobee_tstat_csv/widgets/app_bar.dart';
import 'package:ecobee_tstat_csv/widgets/section_card.dart';
import 'package:ecobee_tstat_csv/widgets/tip_text.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

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
  }); 

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
                } else if (currentHeader == "Heat Stage 2 (sec)" &&
                    numericValue > 0) {
                  cellRange.cellStyle.backColor = '#ffe5e8';
                } else if (currentHeader == "Aux Heat 1 (sec)" &&
                    numericValue > 0) {
                  cellRange.cellStyle.backColor = '#ffe5e8';
                } else if (currentHeader == "Aux Heat 2 (sec)" &&
                    numericValue > 0) {
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
      appBar: ConsistentAppBar(currentPage: "Home"),
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
                      cursor:
                          (_latestVersion != null &&
                              !_isUpToDate(widget.version, _latestVersion!))
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      child: GestureDetector(
                        onTap: () {
                          if (_latestVersion != null &&
                              !_isUpToDate(widget.version, _latestVersion!)) {
                            html.window.location.reload();
                          }
                        },
                        child: Text(
                          // Changed from SelectableText to Text
                          displayVersionText,
                          style: TextStyle(
                            color: versionColor,
                            fontSize: 12,
                            fontWeight: versionWeight,
                            decoration:
                                (_latestVersion != null &&
                                    !_isUpToDate(
                                      widget.version,
                                      _latestVersion!,
                                    ))
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                SectionCard(
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
                  SectionCard(
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
                              child: TipText(
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
                              child: TipText(
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
                                  child: TipText(
                                    "Number of Thermostat Reboots: $_rebootCount",
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                            ..._rebootDetails.map(
                              (detail) =>
                                  TipText(detail, textAlign: TextAlign.center),
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
