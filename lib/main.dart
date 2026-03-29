import 'dart:convert';
import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:csv/csv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    const MaterialApp(
      title: "ecobee CSV Analyzer",
      home: ExcelProcessorApp(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class ExcelProcessorApp extends StatefulWidget {
  const ExcelProcessorApp({super.key});

  @override
  State<ExcelProcessorApp> createState() => _ExcelProcessorAppState();
}

class _ExcelProcessorAppState extends State<ExcelProcessorApp> {
  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  bool _isDragging = false;
  bool _isProcessing = false;
  String _statusMessage = "Drag & Drop CSV Here \nor\n Click to Upload";

  void _pickFile() {
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
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

      List<int> columnsToSkip = [];
      if (csvRows.length >= 6) {
        List<dynamic> headerRow = csvRows[5];
        for (int j = 0; j < headerRow.length; j++) {
          String headerText = headerRow[j].toString().toLowerCase().trim();
          if (headerText.contains("wind speed (km/h)")) {
            columnsToSkip.add(j);
          }
        }
      }

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
              final xlsio.Range headerRange = sheet.getRangeByIndex(1, targetCol, 6, targetCol);
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
              } else {
                cellRange.setText(cellText);
              }

              if (i >= 6) {
                if (targetCol == 3) {
                  if (cellText == "heat") {
                    cellRange.cellStyle.backColor = '#ffe699';
                    cellRange.cellStyle.fontColor = '#a51a18';
                  } else if (cellText == "off") {
                    cellRange.cellStyle.backColor = '#e6f1df';
                    cellRange.cellStyle.fontColor = '#a51a18';
                  } else if (cellText == "auto") {
                    cellRange.cellStyle.backColor = '#CBC3E3';
                  }
                } else if (targetCol == 4) {
                  if (cellText == "heatOff") {
                    cellRange.cellStyle.backColor = '#ffe8ea';
                  } else if (cellText == "heatStage1On") {
                    cellRange.cellStyle.backColor = '#ffe5e8';
                  }
                } else if (targetCol == 5) {
                  if (cellText.contains("smartHome")) {
                    cellRange.cellStyle.backColor = '#f7c8ab';
                  } else if (cellText.contains("smartAway")) {
                    cellRange.cellStyle.backColor = '#d3b5e9';
                  }
                  if (cellText.length > 4) hasLongCalendarContent = true;
                } else if (targetCol == 6) {
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

      if (csvRows.length >= 7) sheet.getRangeByIndex(7, 1).freezePanes();

      final List<int> outBytes = workbook.saveAsStream();
      final blob = html.Blob([outBytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);

      String baseName = fileName.replaceAll(RegExp(r'\.(csv|xlsx)$', caseSensitive: false), '');
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

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
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
          const Text("• ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                _buildSectionCard(
                  title: "About the Analyzer",
                  children: [
                    Text(
                      "A web app to enhance thermostat system monitoring reports to become more readable and efficiently diagnose issues.",
                      style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
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
                  onDragEntered: (details) => setState(() => _isDragging = true),
                  onDragExited: (details) => setState(() => _isDragging = false),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _pickFile,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 300,
                        width: 600,
                        decoration: BoxDecoration(
                          color: _isDragging ? Colors.blue.withOpacity(0.05) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _isDragging ? Colors.blueAccent : Colors.blueGrey.shade200,
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
                            const SizedBox(height: 20),
                            Text(
                              _statusMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  title: "User Tips & How to Use",
                  children: [
                    _buildTip("Upload your ecobee CSV Temperature Report by dragging it into the box above or clicking the box to browse."),
                    _buildTip("To locate your CSV file more easily, sort your folder by 'Date Modified' to see your most recent downloads first."),
                    _buildTip("The app automatically saves your report as an .xlsx file instead of a .csv file. To have future reports open instantly, right-click the file in Chrome's 'Recent Download History' and select 'Always open files of this type.'"),
                    _buildTip("This web app is updated occasionally. To ensure you are seeing the latest version, you may need to clear your browser cache. On Chrome for Windows, press CTRL + F5 for a hard refresh."),
                    _buildTip("Please reach out to Jonathan Lam on Slack to report any issues or to provide feedback."),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  "Developed by Jonathan Lam",
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}