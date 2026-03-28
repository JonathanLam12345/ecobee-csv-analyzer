import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:csv/csv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(const MaterialApp(
    home: ExcelProcessorApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class ExcelProcessorApp extends StatefulWidget {
  const ExcelProcessorApp({super.key});

  @override
  State<ExcelProcessorApp> createState() => _ExcelProcessorAppState();
}

class _ExcelProcessorAppState extends State<ExcelProcessorApp> {
  bool _isDragging = false;
  bool _isProcessing = false;
  String _statusMessage = "Drag & Drop or Click to upload CSV";

  // HTML File Picker for Click-to-Upload
  void _pickFile() {
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = '.csv';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
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

      int maxColumns = 0;
      double maxHeaderLength = 0;
      bool hasLongCalendarContent = false;

      // Calculate tight row height based on rotated headers
      if (csvRows.length >= 6) {
        for (var cell in csvRows[5]) {
          double length = cell?.toString().length.toDouble() ?? 0;
          if (length > maxHeaderLength) maxHeaderLength = length;
        }
        double calculatedHeight = (maxHeaderLength * 3.2).clamp(20.0, 120.0);
        sheet.setRowHeightInPixels(6, calculatedHeight);
      }

      bool highlightedCoolSet = false;
      bool highlightedHeatSet = false;
      bool highlightedCurrentTemp = false;
      bool highlightedThermostatTemp = false;

      for (int i = 0; i < csvRows.length; i++) {
        final List<dynamic> rowData = csvRows[i];
        if (rowData.length > maxColumns) maxColumns = rowData.length;

        for (int j = 0; j < rowData.length; j++) {
          final dynamic rawValue = rowData[j];
          final String cellText = rawValue?.toString() ?? "";

          // Process Header Row (Row 6)
          if (i == 5) {
            String? hexColor;
            if (!highlightedCoolSet && cellText.contains("Cool Set Temp")) {
              hexColor = '#496daf';
              highlightedCoolSet = true;
            } else if (!highlightedHeatSet && cellText.contains("Heat Set Temp")) {
              hexColor = '#fe4949';
              highlightedHeatSet = true;
            } else if (!highlightedCurrentTemp && cellText.contains("Current Temp")) {
              hexColor = '#ffff00';
              highlightedCurrentTemp = true;
            } else if (!highlightedThermostatTemp && cellText.contains("Thermostat Temperature")) {
              hexColor = '#ffff00';
              highlightedThermostatTemp = true;
            }

            if (j >= 4) {
              final xlsio.Range headerRange = sheet.getRangeByIndex(1, j + 1, 6, j + 1);
              headerRange.merge();
              headerRange.setText(cellText);
              headerRange.cellStyle.rotation = 90;
              headerRange.cellStyle.vAlign = xlsio.VAlignType.bottom;
              headerRange.cellStyle.hAlign = xlsio.HAlignType.center;
              if (hexColor != null) headerRange.cellStyle.backColor = hexColor;
            } else {
              final cellRange = sheet.getRangeByIndex(i + 1, j + 1);
              cellRange.setText(cellText);
              if (hexColor != null) cellRange.cellStyle.backColor = hexColor;
            }
          } else {
            // Process Data Rows & Top Metadata Rows
            if (i >= 6 || j < 4) {
              final cellRange = sheet.getRangeByIndex(i + 1, j + 1);

              // Skip converting the serial number to an integer
              if (i == 0 && j == 3) {
                cellRange.setText(cellText);
              } else {
                final double? numericValue = double.tryParse(cellText);
                if (numericValue != null) {
                  cellRange.setNumber(numericValue);
                } else {
                  cellRange.setText(cellText);
                }

                // Apply Conditional Formatting for Data Rows (Index 6+)
                if (i >= 6) {
                  if (j == 2) { // Column C: System Setting
                    if (cellText == "heat") {
                      cellRange.cellStyle.backColor = '#ffe699';
                      cellRange.cellStyle.fontColor = '#a51a18';
                    } else if (cellText == "off") {
                      cellRange.cellStyle.backColor = '#e6f1df';
                      cellRange.cellStyle.fontColor = '#a51a18';
                    }
                  } else if (j == 3) { // Column D: System Mode
                    if (cellText == "heatOff") {
                      cellRange.cellStyle.backColor = '#ffe8ea';
                    } else if (cellText == "heatStage1On") {
                      cellRange.cellStyle.backColor = '#ffe5e8';
                    }
                  } else if (j == 4) { // Column E: Calendar Event
                    if (cellText == "smartHome") {
                      cellRange.cellStyle.backColor = '#f7c8ab';
                    }
                    if (cellText.length > 4) {
                      hasLongCalendarContent = true;
                    }
                  } else if (j == 5) { // Column F: Program Mode
                    if (cellText == "Sleep") {
                      cellRange.cellStyle.backColor = '#a9d08e';
                    } else if (cellText == "Away") {
                      cellRange.cellStyle.backColor = '#cdace6';
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Auto-fit logic with length check for Calendar Event column
      for (int col = 1; col <= maxColumns; col++) {
        sheet.autoFitColumn(col);
        final xlsio.Range colRange = sheet.getRangeByIndex(6, col);
        final String headerText = colRange.getText() ?? "";

        if (headerText.contains("Calendar Event") && hasLongCalendarContent) {
          double autoWidth = colRange.columnWidth;
          colRange.columnWidth = autoWidth / 2;
        }
      }

      if (csvRows.length >= 7) {
        sheet.getRangeByIndex(7, 1).freezePanes();
      }

      final List<int> outBytes = workbook.saveAsStream();
      final blob = html.Blob([outBytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);

      String baseName = fileName.replaceAll(RegExp(r'\.(csv|xlsx)$', caseSensitive: false), '');
      String downloadName = "$baseName(new).xlsx";

      html.AnchorElement(href: url)
        ..setAttribute("download", downloadName)
        ..click();

      html.Url.revokeObjectUrl(url);

      setState(() => _statusMessage = "Conversion Successful!");
      await Future.delayed(const Duration(seconds: 3));

      setState(() {
        _statusMessage = "Drag & Drop or Click to upload CSV";
        _isDragging = false;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _statusMessage = "Error: ${e.toString()}");
    } finally {
      workbook?.dispose();
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("ecobee CSV Analyzer"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Center(
        child: DropTarget(
          onDragDone: (details) async {
            if (details.files.isNotEmpty) {
              final file = details.files.first;
              final bytes = await file.readAsBytes();
              await _processFile(bytes, file.name);
            }
          },
          onDragEntered: (details) => setState(() => _isDragging = true),
          onDragExited: (details) => setState(() => _isDragging = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _pickFile,
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 350,
                width: 550,
                decoration: BoxDecoration(
                  color: _isDragging ? Colors.blue.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isDragging ? Colors.blueAccent : Colors.grey.shade300,
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
                        color: _isDragging ? Colors.blueAccent : Colors.blueGrey[200],
                      ),
                    const SizedBox(height: 24),
                    Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}