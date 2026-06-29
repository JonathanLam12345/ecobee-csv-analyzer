import 'dart:convert';
import 'dart:html' as html;

import 'package:csv/csv.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:ecobee_tstat_csv/widgets/chatbot_widget.dart';
import 'package:ecobee_tstat_csv/widgets/app_bar.dart';
import 'package:ecobee_tstat_csv/widgets/section_card.dart';
import 'package:ecobee_tstat_csv/widgets/support_chat_widget.dart';
import 'package:ecobee_tstat_csv/widgets/tip_text.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:ecobee_tstat_csv/widgets/expandable_section_card.dart';
import 'package:http/http.dart' as http;

// 411955672402--2026-01-01--2026-01-30-reports-data


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
  bool _isChatOpen = false;
  String _statusMessage = "Drag & Drop CSV Here \nor\n Click to Upload";
  double? _totalFanHours;

  // Add these new variables:
  double? _totalCool1Hours;
  double? _totalCool2Hours;
  double? _totalHeat1Hours;
  double? _totalHeat2Hours;
  double? _totalAux1Hours;
  double? _totalAux2Hours;

  double? _avgHeatSetTemp;
  double? _avgCoolSetTemp;

  String? _serialNumber;
  String? _thermostatName;
  String? _startDate;
  String? _endDate;

  int? _rebootCount;
  int? _rebootsOnHeat;
  int? _rebootsOnCool;
  int? _rebootsOnNone;
  List _rebootDetails = [];

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

  // Logic to show the chatbot as a pop-up
  void _showChatbotPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2),
      // Dim the background slightly
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.bottomRight, // Position it near the FAB
          insetPadding: const EdgeInsets.only(right: 20, bottom: 80),
          child: const SizedBox(
            width: 400,
            height: 500,
            child: ChatbotWidget(),
          ),
        );
      },
    );
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
      final List<List<dynamic>> csvRows = CsvToListConverter(
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

      // 1. Reset variables at the start of processing
      _totalCool1Hours = null;
      _totalCool2Hours = null;
      _totalHeat1Hours = null;
      _totalHeat2Hours = null;
      _totalAux1Hours = null;
      _totalAux2Hours = null;

      _avgHeatSetTemp = null;
      _avgCoolSetTemp = null;
      _rebootsOnHeat = null;
      _rebootsOnCool = null;
      _rebootsOnNone = null;

      int rebootCounter = 0;
      int rebootsOnHeatCounter = 0;
      int rebootsOnCoolCounter = 0;
      int rebootsOnNoneCounter = 0;
      bool inRebootPeriod = false;
      List<Map<String, String>> currentRebootDetails = [];

      String rebootStartDate = "";
      String rebootStartTime = "";

// Track the runtime state of the LAST valid row
      bool lastStateWasHeating = false;
      bool lastStateWasCooling = false;

// Find the runtime column indexes early so we can evaluate equipment state
      List<dynamic> earlyHeaderRow =
          csvRows.length >= 6 ? csvRows[5] : <dynamic>[];
      int rCool1Idx = earlyHeaderRow.indexOf("Cool Stage 1 (sec)");
      int rCool2Idx = earlyHeaderRow.indexOf("Cool Stage 2 (sec)");
      int rHeat1Idx = earlyHeaderRow.indexOf("Heat Stage 1 (sec)");
      int rHeat2Idx = earlyHeaderRow.indexOf("Heat Stage 2 (sec)");
      int rAux1Idx = earlyHeaderRow.indexOf("Aux Heat 1 (sec)");
      int rAux2Idx = earlyHeaderRow.indexOf("Aux Heat 2 (sec)");

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

            // Evaluate the equipment state right before the reboot happened
            String rebootType = "None";
            if (lastStateWasHeating) {
              rebootType = "Heat";
              rebootsOnHeatCounter++;
            } else if (lastStateWasCooling) {
              rebootType = "Cool";
              rebootsOnCoolCounter++;
            } else {
              rebootsOnNoneCounter++;
            }

            // Save the structured data
            currentRebootDetails.add({
              'date': rebootStartDate,
              'time': rebootStartTime,
              'type': rebootType
            });
          }

          // Reset the flag so we can catch the next gap
          inRebootPeriod = false;

          // --- Check THIS row's runtimes to save for the NEXT potential reboot ---
          double c1 = 0, c2 = 0, h1 = 0, h2 = 0, a1 = 0, a2 = 0;

          if (rCool1Idx != -1 && rCool1Idx < row.length)
            c1 = double.tryParse(row[rCool1Idx].toString()) ?? 0;
          if (rCool2Idx != -1 && rCool2Idx < row.length)
            c2 = double.tryParse(row[rCool2Idx].toString()) ?? 0;
          if (rHeat1Idx != -1 && rHeat1Idx < row.length)
            h1 = double.tryParse(row[rHeat1Idx].toString()) ?? 0;
          if (rHeat2Idx != -1 && rHeat2Idx < row.length)
            h2 = double.tryParse(row[rHeat2Idx].toString()) ?? 0;
          if (rAux1Idx != -1 && rAux1Idx < row.length)
            a1 = double.tryParse(row[rAux1Idx].toString()) ?? 0;
          if (rAux2Idx != -1 && rAux2Idx < row.length)
            a2 = double.tryParse(row[rAux2Idx].toString()) ?? 0;

          lastStateWasCooling = (c1 > 0 || c2 > 0);
          lastStateWasHeating = (h1 > 0 || h2 > 0 || a1 > 0 || a2 > 0);
        }
      }
      // --------------------------------------

      // Update state at the end of processing
      setState(() {
        _rebootCount = rebootCounter;
        _rebootsOnHeat = rebootsOnHeatCounter;
        _rebootsOnCool = rebootsOnCoolCounter;
        _rebootsOnNone = rebootsOnNoneCounter;
        _rebootDetails = currentRebootDetails;
      });

      //csvRows[0].length >= 4
      // This counts the number of items (columns) inside that specific row.
      if (csvRows.length >= 4 &&
          csvRows[0].length >= 4 &&
          csvRows[1].length >= 4 &&
          csvRows[2].length >= 4 &&
          csvRows[3].length >= 4) {
        _serialNumber = csvRows[0][3].toString();
        _thermostatName = csvRows[1][3].toString();
        _startDate = csvRows[2][3].toString();
        _endDate = csvRows[3][3].toString();
      }

      List<int> columnsToSkip = [];

      //csvRows.length >= 6
      //Counts the num of rows
// Counts the num of rows
      if (csvRows.length >= 6) {
        List<dynamic> headerRow = csvRows[5];

        // 1. Find indexes (-1 means it didn't find the column)
        int cool1Idx = headerRow.indexOf("Cool Stage 1 (sec)");
        int cool2Idx = headerRow.indexOf("Cool Stage 2 (sec)");
        int heat1Idx = headerRow.indexOf("Heat Stage 1 (sec)");
        int heat2Idx = headerRow.indexOf("Heat Stage 2 (sec)");
        int aux1Idx = headerRow.indexOf("Aux Heat 1 (sec)");
        int aux2Idx = headerRow.indexOf("Aux Heat 2 (sec)");

        int heatSetTempIdx = -1;
        int coolSetTempIdx = -1;

        for (int j = 0; j < headerRow.length; j++) {
          String headerText = headerRow[j].toString().toLowerCase().trim();
          if (headerText.contains("wind speed (km/h)")) {
            columnsToSkip.add(j);
          }
          if (headerRow[j].toString().trim() == "Fan (sec)") {
            fanSecIndex = j;
          }
          if (headerText.contains("heat set temp")) {
            heatSetTempIdx = j;
          }
          if (headerText.contains("cool set temp")) {
            coolSetTempIdx = j;
          }
        }

        // Variables to hold the raw second counts while we loop
        double totalCool1Seconds = 0;
        double totalCool2Seconds = 0;
        double totalHeat1Seconds = 0;
        double totalHeat2Seconds = 0;
        double totalAux1Seconds = 0;
        double totalAux2Seconds = 0;

        double sumHeatSetTemp = 0;
        int countHeatSetTemp = 0;
        double sumCoolSetTemp = 0;
        int countCoolSetTemp = 0;
        List<List<dynamic>> dataRows = csvRows.sublist(6);

        // =========================================================
        // NOTICE HOW THE LOOP IS NOW INSIDE THIS IF BLOCK
        // =========================================================

        for (int i = 6; i < csvRows.length; i++) {
          // Fan
          if (fanSecIndex != null && fanSecIndex! < csvRows[i].length) {
            final double? val =
                double.tryParse(csvRows[i][fanSecIndex!].toString());
            if (val != null) totalFanSeconds += val;
          }

          // Cool Stage 1 (Checking for != -1 instead of null)
          if (cool1Idx != -1 && cool1Idx < csvRows[i].length) {
            final double? val =
                double.tryParse(csvRows[i][cool1Idx].toString());
            if (val != null) totalCool1Seconds += val;
          }

          // Cool Stage 2
          if (cool2Idx != -1 && cool2Idx < csvRows[i].length) {
            final double? val =
                double.tryParse(csvRows[i][cool2Idx].toString());
            if (val != null) totalCool2Seconds += val;
          }

          // Heat Stage 1
          if (heat1Idx != -1 && heat1Idx < csvRows[i].length) {
            final double? val =
                double.tryParse(csvRows[i][heat1Idx].toString());
            if (val != null) totalHeat1Seconds += val;
          }

          // Heat Stage 2
          if (heat2Idx != -1 && heat2Idx < csvRows[i].length) {
            final double? val =
                double.tryParse(csvRows[i][heat2Idx].toString());
            if (val != null) totalHeat2Seconds += val;
          }

          // Aux Heat 1
          if (aux1Idx != -1 && aux1Idx < csvRows[i].length) {
            final double? val = double.tryParse(csvRows[i][aux1Idx].toString());
            if (val != null) totalAux1Seconds += val;
          }

          // Aux Heat 2
          if (aux2Idx != -1 && aux2Idx < csvRows[i].length) {
            final double? val = double.tryParse(csvRows[i][aux2Idx].toString());
            if (val != null) totalAux2Seconds += val;
          }

          if (heatSetTempIdx != -1 && heatSetTempIdx < csvRows[i].length) {
            final double? val =
                double.tryParse(csvRows[i][heatSetTempIdx].toString());
            if (val != null) {
              sumHeatSetTemp += val;
              countHeatSetTemp++;
            }
          }

          if (coolSetTempIdx != -1 && coolSetTempIdx < csvRows[i].length) {
            final double? val =
                double.tryParse(csvRows[i][coolSetTempIdx].toString());
            if (val != null) {
              sumCoolSetTemp += val;
              countCoolSetTemp++;
            }
          }
        }

        // Don't forget to set your state right here before the block closes!
        setState(() {
          if (fanSecIndex != null) _totalFanHours = totalFanSeconds / 3600;
          if (cool1Idx != -1) _totalCool1Hours = totalCool1Seconds / 3600;
          if (cool2Idx != -1) _totalCool2Hours = totalCool2Seconds / 3600;
          if (heat1Idx != -1) _totalHeat1Hours = totalHeat1Seconds / 3600;
          if (heat2Idx != -1) _totalHeat2Hours = totalHeat2Seconds / 3600;
          if (aux1Idx != -1) _totalAux1Hours = totalAux1Seconds / 3600;
          if (aux2Idx != -1) _totalAux2Hours = totalAux2Seconds / 3600;

          if (countHeatSetTemp > 0)
            _avgHeatSetTemp = sumHeatSetTemp / countHeatSetTemp;
          if (countCoolSetTemp > 0)
            _avgCoolSetTemp = sumCoolSetTemp / countCoolSetTemp;
        });
      } // <-- The entire csvRows.length >= 6 block finally closes here!

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
      List<int> localParts =
          local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> remoteParts =
          remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  children: [
                    MouseRegion(
                          // The cursor will now correctly show the pointer/hand
                          cursor: (_latestVersion != null &&
                                  !_isUpToDate(widget.version, _latestVersion!))
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.basic,
                          child: GestureDetector(
                            onTap: () {
                              if (_latestVersion != null &&
                                  !_isUpToDate(
                                      widget.version, _latestVersion!)) {
                                html.window.location.reload();
                              }
                            },
                            child:

                            Align(
                              alignment: Alignment.centerRight, // This forces the widget to the right side
                              child: Text(
                                displayVersionText,
                                style: TextStyle(
                                  color: versionColor,
                                  fontSize: 12,
                                  fontWeight: versionWeight,
                                  decoration: (_latestVersion != null &&
                                      !_isUpToDate(
                                        widget.version,
                                        _latestVersion!,
                                      ))
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                              ),
                            )

                          ),
                        ),
SizedBox(height: 30,),

                    //
                    // SectionCard(
                    //   title: "About CSV Analyzer",
                    //   children: [
                    //     Text(
                    //       "A web app designed to transform raw ecobee thermostat system monitoring data into a clear and readable report for faster and more accurate diagnostics.",
                    //       style: TextStyle(
                    //         color: Colors.blueGrey.shade600,
                    //         fontSize: 12,
                    //       ),
                    //     ),
                    //   ],
                    // ),
                    // const SizedBox(height: 24),
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
                            height: 200,
                            width: 420,
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
                                    fontSize: 16,
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

                    // ==========================================
                    // 1. THERMOSTAT REPORT SUMMARY CARD
                    // ==========================================
                    if (_serialNumber != null)
                      Wrap(
                          spacing: 24.0,
                          // The horizontal gap between the cards
                          runSpacing: 24.0,
                          // The vertical gap when a card gets pushed to the next row
                          alignment: WrapAlignment.spaceBetween,
                          // Centers the cards in the available space
                          children: [
                            ExpandableSectionCard(
                              maxWidth: 350,
                              title: "Thermostat Report Summary",
                              titleBackgroundColor: Colors.grey.shade300,
                              titleColor: Colors.black,
                              initiallyExpanded: true,
                              children: [
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: Container(
                                      width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFF00),
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          Border.all(color: Colors.black12),
                                    ),
                                    child: TipText(
                                      "Thermostat Serial Number: $_serialNumber",
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFF00),
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          Border.all(color: Colors.black12),
                                    ),
                                    child: TipText(
                                      "Thermostat Name: $_thermostatName",
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                ),
                                if (_startDate != null)
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4, horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFFF00),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border:
                                            Border.all(color: Colors.black12),
                                      ),
                                      child: TipText(
                                        "Start Date: $_startDate",
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                  ),
                                if (_endDate != null)
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4, horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFFF00),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border:
                                            Border.all(color: Colors.black12),
                                      ),
                                      child: TipText(
                                        "End Date: $_endDate",
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                            // ==========================================
                            // 2. HVAC SYSTEM RUNTIME CARD
                            // ==========================================
                            if (_serialNumber != null)
                              ExpandableSectionCard(
                                maxWidth: 380,
                                title: "Overall Stats",
                                titleBackgroundColor: Colors.blueGrey.shade100,
                                // Giving this its own header color
                                titleColor: Colors.black,
                                initiallyExpanded: true,
                                children: [


                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 5.0),
                                      child: Text(
                                        "Reboots",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600, // Medium-bold weight looks cleaner than standard bold
                                          color: Colors.blueGrey.shade800,
                                          letterSpacing: 0.5, // Adds a slight modern touch
                                        ),
                                      ),
                                    ),
                                  ),

                                  if (_rebootCount != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                        const EdgeInsets.only(bottom: 16),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF5350),
                                          borderRadius:
                                          BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                          "Total Reboots: $_rebootCount",
                                          textAlign: TextAlign.left,
                                        ),
                                      ),
                                    ),

                                  if (_rebootsOnHeat != null &&
                                      _rebootCount! > 0)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                        const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE5E8),
                                          // Light Red
                                          borderRadius:
                                          BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Rebooting on heating calls: $_rebootsOnHeat",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),

                                  if (_rebootsOnNone != null &&
                                      _rebootCount! > 0)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                        const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F4F6),
                                          // Neutral Grey
                                          borderRadius:
                                          BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Rebooting on no equipment running: $_rebootsOnNone",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),

                                  if (_rebootsOnCool != null &&
                                      _rebootCount! > 0)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                        const EdgeInsets.only(bottom: 16),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFCADFF2),
                                          // Light Blue
                                          borderRadius:
                                          BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Rebooting on cooling calls: $_rebootsOnCool",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),

                                  Divider(
                                    height: 3,
                                    // Vertical layout space allocating 16px above and 16px below line
                                    thickness: 1,
                                    // Definite thin border profile
                                    color: Colors
                                        .black12, // Standard subtle layout line matching app themes
                                  ),

                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                                      child: Text(
                                        "Runtimes",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600, // Medium-bold weight looks cleaner than standard bold
                                          color: Colors.blueGrey.shade800,
                                          letterSpacing: 0.5, // Adds a slight modern touch
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_totalFanHours != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFC6E0B4),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                          "Fan: ${(_totalFanHours! * 3600).toInt()} seconds (${_totalFanHours!.toStringAsFixed(2)} hours)",
                                          textAlign: TextAlign.left,
                                        ),
                                      ),
                                    ),

                                  // COOLING STAGES
                                  if (_totalCool1Hours != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFCADFF2),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Cool (Stage 1): ${(_totalCool1Hours! * 3600).toInt()} seconds (${_totalCool1Hours!.toStringAsFixed(2)} hours)",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),
                                  if (_totalCool2Hours != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFCADFF2),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Cool (Stage 2): ${(_totalCool2Hours! * 3600).toInt()} seconds (${_totalCool2Hours!.toStringAsFixed(2)} hours)",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),

                                  // HEATING STAGES
                                  if (_totalHeat1Hours != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE5E8),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Heat (Stage 1): ${(_totalHeat1Hours! * 3600).toInt()} seconds (${_totalHeat1Hours!.toStringAsFixed(2)} hours)",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),
                                  if (_totalHeat2Hours != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE5E8),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Heat (Stage 2): ${(_totalHeat2Hours! * 3600).toInt()} seconds (${_totalHeat2Hours!.toStringAsFixed(2)} hours)",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),

                                  // AUX HEATING STAGES
                                  if (_totalAux1Hours != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE5E8),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Aux Heat (Stage 1): ${(_totalAux1Hours! * 3600).toInt()} seconds (${_totalAux1Hours!.toStringAsFixed(2)} hours)",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),
                                  if (_totalAux2Hours != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE5E8),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                            "Aux Heat (Stage 2): ${(_totalAux2Hours! * 3600).toInt()} seconds (${_totalAux2Hours!.toStringAsFixed(2)} hours)",
                                            textAlign: TextAlign.left),
                                      ),
                                    ),

                                  Divider(
                                    height: 3,
                                    // Vertical layout space allocating 16px above and 16px below line
                                    thickness: 1,
                                    // Definite thin border profile
                                    color: Colors
                                        .black12, // Standard subtle layout line matching app themes
                                  ),

                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                                      child: Text(
                                        "Average Set Temperature",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600, // Medium-bold weight looks cleaner than standard bold
                                          color: Colors.blueGrey.shade800,
                                          letterSpacing: 0.5, // Adds a slight modern touch
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_avgHeatSetTemp != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE5E8),
                                          // Light Red
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                          "Heat: ${_avgHeatSetTemp!.toStringAsFixed(1)}°",
                                          textAlign: TextAlign.left,
                                        ),
                                      ),
                                    ),

                                  if (_avgCoolSetTemp != null)
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFCADFF2),
                                          // Light Blue
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black12),
                                        ),
                                        child: TipText(
                                          "Cool: ${_avgCoolSetTemp!.toStringAsFixed(1)}°",
                                          textAlign: TextAlign.left,
                                        ),
                                      ),
                                    ),



                                ],
                              ),

                            if (_serialNumber != null)
                              ExpandableSectionCard(
                                maxWidth: 350,
                                title:
                                    " Reboot Indicators Table (${_rebootCount ?? 0})",
                                titleColor: Colors.black,
                                titleBackgroundColor: const Color(0xFFEF5350),
                                initiallyExpanded: false,
                                // Set to false if you want it closed by default
                                children: [
                                  // You can build your table here using DataTable or a ListView
                                  // For example, mapping through your _rebootDetails list:
                                  if (_rebootDetails.isNotEmpty)
                                    Column(
                                      children: [
                                        Align(
                                          alignment: Alignment.topLeft,
                                          child: Table(
                                            border: TableBorder.all(
                                              color: Colors.grey.shade300,
                                              width: 1,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            columnWidths: const {
                                              0: FixedColumnWidth(60),
                                              // Compact width for the counter column
                                              1: FixedColumnWidth(110),
                                              // Evenly expands to fill the remaining width
                                              2: FixedColumnWidth(110),
                                              // Evenly expands to fill the remaining width
                                            },
                                            defaultVerticalAlignment:
                                                TableCellVerticalAlignment
                                                    .middle,
                                            children: [
                                              // 1. Table Header Row
                                              TableRow(
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                ),
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            10.0),
                                                    child: Text(
                                                      '#',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.blueGrey
                                                              .shade700),
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            10.0),
                                                    child: Text(
                                                      'Start Date',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.blueGrey
                                                              .shade700),
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            10.0),
                                                    child: Text(
                                                      'Start Time',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.blueGrey
                                                              .shade700),
                                                    ),
                                                  ),
                                                ],
                                              ),

                                              // Dynamic Table Data Rows
                                              ..._rebootDetails
                                                  .asMap()
                                                  .entries
                                                  .map((entry) {
                                                final int index = entry.key;
                                                final dynamic detail =
                                                    entry.value;

                                                final String rebootCounter =
                                                    '${index + 1}';
                                                String rebootStartDate = '';
                                                String rebootStartTime = '';
                                                String rebootType = 'None';

                                                // Safely extract from our new Map structure
                                                if (detail is Map) {
                                                  rebootStartDate =
                                                      detail['date']
                                                              ?.toString() ??
                                                          '';
                                                  rebootStartTime =
                                                      detail['time']
                                                              ?.toString() ??
                                                          '';
                                                  rebootType = detail['type']
                                                          ?.toString() ??
                                                      'None';
                                                }

                                                // Determine the row color based on the equipment state
                                                Color rowColor = Colors.white;
                                                if (rebootType == "Heat")
                                                  rowColor = const Color(
                                                      0xFFFFE5E8); // Light Red
                                                if (rebootType == "Cool")
                                                  rowColor = const Color(
                                                      0xFFCADFF2); // Light Blue
                                                if (rebootType == "None")
                                                  rowColor = const Color(
                                                      0xFFF9FAFB); // Neutral Grey

                                                return TableRow(
                                                  decoration: BoxDecoration(
                                                      color: rowColor),
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              10.0),
                                                      child: Text(rebootCounter,
                                                          textAlign:
                                                              TextAlign.center),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              10.0),
                                                      child: Text(
                                                          rebootStartDate,
                                                          textAlign:
                                                              TextAlign.center),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              10.0),
                                                      child: Text(
                                                          rebootStartTime,
                                                          textAlign:
                                                              TextAlign.center),
                                                    ),
                                                  ],
                                                );
                                              }).toList(),
                                            ],
                                          ),
                                        )
                                      ],
                                    )
                                  else
                                    const Text("No Issues Here."),
                                ],
                              ),
                          ],)

                    // const SizedBox(height: 32),
                    // Text(
                    //   "Developed by Jonathan Lam",
                    //   style: TextStyle(
                    //     color: Colors.blueGrey.shade400,
                    //     fontSize: 9,
                    //     fontWeight: FontWeight.w500,
                    //   ),
                    // ),
                    //   SizedBox(height: 200),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: _isChatOpen
                ? SupportChatWidget(
                    onClose: () => setState(() => _isChatOpen = false))
                : FloatingActionButton.extended(
                    onPressed: () => setState(() => _isChatOpen = true),
                    label: const Text('Ask ecobee AI'),
                    icon: const Icon(Icons.smart_toy),
                    backgroundColor: Colors.green,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(String text, {Color color = const Color(0xFFFFFF00)}) {
    return Align(
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.60,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black12),
          ),
          child: TipText(text, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class KnowledgeBaseService {
  Future<List<KnowledgeItem>> loadKnowledgeBase() async {
    final rawJson =
        await rootBundle.loadString('assets/data/knowledge_base.json');

    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final chunkList = decoded['chunks'] as List<dynamic>? ?? [];

    return chunkList
        .map((item) => KnowledgeItem.fromMap(item as Map<String, dynamic>))
        .toList();
  }
}

class LocalSearchService {
  List<SearchResult> retrieveTopMatches(
    List<KnowledgeItem> items,
    String query, {
    int limit = 5,
  }) {
    final results = items
        .map((item) => SearchResult(item: item, score: _scoreItem(item, query)))
        .where((result) => result.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return results.take(limit).toList();
  }

  int _scoreItem(KnowledgeItem item, String query) {
    final q = query.toLowerCase().trim();
    final tokens = _tokenize(query);
    int score = 0;

    if (item.title.toLowerCase().contains(q)) score += 10;
    if (item.content.toLowerCase().contains(q)) score += 7;
    if (item.category.toLowerCase().contains(q)) score += 4;
    if (item.tags.any((tag) =>
        tag.toLowerCase().contains(q) || q.contains(tag.toLowerCase()))) {
      score += 8;
    }

    for (final token in tokens) {
      if (item.title.toLowerCase().contains(token)) score += 3;
      if (item.content.toLowerCase().contains(token)) score += 2;
      if (item.category.toLowerCase().contains(token)) score += 2;
      if (item.tags.any((tag) => tag.toLowerCase().contains(token))) score += 3;
    }

    return score;
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }
}

class GeminiService {
  Future<String> generateGroundedReply({
    required String apiKey,
    required String userQuery,
    required List<SearchResult> matches,
  }) async {
    final context = matches.map((result) {
      final item = result.item;
      return [
        'ID: ${item.id}',
        'Title: ${item.title}',
        'Category: ${item.category}',
        'Tags: ${item.tags.join(', ')}',
        'Score: ${result.score}',
        'Content: ${item.content}',
        'Source: ${item.source}',
      ].join('\n');
    }).join('\n\n---\n\n');

    final prompt = '''You are a friendly AI support assistant.

Handle messages in two modes:

MODE 1: Casual conversation
If the user is greeting, thanking, confirming, or making small talk, respond naturally and briefly. No knowledge base lookup is required for simple social messages.

MODE 2: Support and factual questions
If the user is asking for help, instructions, troubleshooting, product information, policy details, or other factual guidance, use the provided knowledge base context as your first source.

When answering support questions:
- Use the knowledge base first whenever relevant information is available.
- If the knowledge base answer is sufficient, answer from it naturally and clearly.
- If the knowledge base answer is partial or missing, say so explicitly.
- Then provide a fallback answer from your general knowledge with a short warning that it was not found in the knowledge base.

Fallback wording:
“I couldn not find a clear answer in the knowledge base. I will try to help based on my general understanding, but this may be less reliable than an answer taken directly from the support articles.”

Additional rules:
- Never invent knowledge base content.
- Never say you found something in the knowledge base if you did not.
- Ask a clarifying question if needed.
- Keep answers direct, natural, and helpful.
- For greetings, do not sound formal or scripted.
- If the user is asking for anything unrelated to thermostats or ecobee products, politely let them know you are specialized in those topics and may not be able to help with unrelated questions.

Database context:
${context.isEmpty ? 'No matching database records were found.' : context}

User question:
$userQuery''';

    final response = await http.post(
      Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('No candidates returned by Gemini.');
    }

    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw Exception('No text parts returned by Gemini.');
    }

    final text = parts
        .map((part) => (part as Map<String, dynamic>)['text'])
        .whereType<String>()
        .join('\n');

    if (text.trim().isEmpty) {
      throw Exception('Gemini returned an empty response.');
    }

    return text.trim();
  }
}

class KnowledgeItem {
  const KnowledgeItem({
    required this.id,
    required this.title,
    required this.category,
    required this.tags,
    required this.content,
    required this.source,
  });

  final String id;
  final String title;
  final String category;
  final List<String> tags;
  final String content;
  final String source;

  factory KnowledgeItem.fromMap(Map<String, dynamic> map) {
    return KnowledgeItem(
      id: (map['chunk_id'] ?? map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      tags: ((map['tags'] as List<dynamic>?) ?? [])
          .map((tag) => tag.toString())
          .toList(),
      content: (map['content'] ?? '').toString(),
      source: (map['url'] ?? map['source'] ?? '').toString(),
    );
  }
}

class SearchResult {
  const SearchResult({required this.item, required this.score});

  final KnowledgeItem item;
  final int score;
}

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  final ChatRole role;
  final String text;
}
