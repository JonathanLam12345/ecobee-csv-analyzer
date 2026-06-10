import 'dart:convert';
import 'dart:html' as html;

import 'package:csv/csv.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:ecobee_tstat_csv/widgets/app_bar.dart';
import 'package:ecobee_tstat_csv/widgets/expandable_section_card.dart';
import 'package:ecobee_tstat_csv/widgets/section_card.dart';
import 'package:ecobee_tstat_csv/widgets/tip_text.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final info = await PackageInfo.fromPlatform();
  final String appVersion = info.version;

  final fontLoader = FontLoader('MaterialIcons');
  await fontLoader.load();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyA9faf7iTLDrH9MHlqr7Ro6SjvSOhMYGlg',
      authDomain: 'ecobee-csv-analyzer.firebaseapp.com',
      projectId: 'ecobee-csv-analyzer',
      storageBucket: 'ecobee-csv-analyzer.firebasestorage.app',
      messagingSenderId: '296794280928',
      appId: '1:296794280928:web:c38d5cf609cbfeb56e5185',
      measurementId: 'G-9VLF1JLCVW',
    ),
  );

  runApp(
    MaterialApp(
      title: 'ecobee CSV Analyzer',
      home: ExcelProcessorApp(version: appVersion),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class ExcelProcessorApp extends StatefulWidget {
  const ExcelProcessorApp({super.key, required this.version});

  final String version;

  @override
  State<ExcelProcessorApp> createState() => _ExcelProcessorAppState();
}

class _ExcelProcessorAppState extends State<ExcelProcessorApp> {
  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  bool _isDragging = false;
  bool _isProcessing = false;
  bool _isChatOpen = false;

  String _statusMessage = 'Drag & Drop CSV Here \nor\n Click to Upload';

  double? _totalFanHours;
  double? _totalCool1Hours;
  double? _totalCool2Hours;
  double? _totalHeat1Hours;
  double? _totalHeat2Hours;
  double? _totalAux1Hours;
  double? _totalAux2Hours;

  String? _serialNumber;
  String? _thermostatName;
  String? _startDate;
  String? _endDate;

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
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = '.csv';
    uploadInput.click();

    uploadInput.onChange.listen((_) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        analytics.logEvent(name: 'file_picked_manually');
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        reader.onLoadEnd.listen((_) async {
          final Uint8List bytes = reader.result as Uint8List;
          await _processFile(bytes, file.name);
        });
      }
    });
  }

  Future<void> _processFile(Uint8List bytes, String fileName) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing CSV...';
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

      if (csvRows.isEmpty) {
        throw Exception('File is empty');
      }

      workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];

      _totalCool1Hours = null;
      _totalCool2Hours = null;
      _totalHeat1Hours = null;
      _totalHeat2Hours = null;
      _totalAux1Hours = null;
      _totalAux2Hours = null;

      int rebootCounter = 0;
      bool inRebootPeriod = false;
      final List<String> currentRebootDetails = [];
      String rebootStartDate = '';
      String rebootStartTime = '';

      for (int i = 6; i < csvRows.length; i++) {
        final row = csvRows[i];
        if (row.length < 11) continue;

        final String colC = row[2].toString().trim();
        final String colK = row[10].toString().trim();

        final bool isRebootRow = colC.isEmpty && colK.isNotEmpty;
        final bool isOnline = colC.isNotEmpty;

        if (isRebootRow && !inRebootPeriod) {
          rebootStartDate = row[0].toString();
          rebootStartTime = row[1].toString();
          inRebootPeriod = true;
        } else if (isOnline && inRebootPeriod) {
          rebootCounter++;
          currentRebootDetails.add('$rebootStartDate $rebootStartTime');
          inRebootPeriod = false;
        }
      }

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

      int? fanSecIndex;
      double totalFanSeconds = 0;
      double totalCool1Seconds = 0;
      double totalCool2Seconds = 0;
      double totalHeat1Seconds = 0;
      double totalHeat2Seconds = 0;
      double totalAux1Seconds = 0;
      double totalAux2Seconds = 0;
      final List<int> columnsToSkip = [];

      if (csvRows.length >= 6) {
        final headerRow = csvRows[5];

        final int cool1Idx = headerRow.indexOf('Cool Stage 1 (sec)');
        final int cool2Idx = headerRow.indexOf('Cool Stage 2 (sec)');
        final int heat1Idx = headerRow.indexOf('Heat Stage 1 (sec)');
        final int heat2Idx = headerRow.indexOf('Heat Stage 2 (sec)');
        final int aux1Idx = headerRow.indexOf('Aux Heat 1 (sec)');
        final int aux2Idx = headerRow.indexOf('Aux Heat 2 (sec)');

        for (int j = 0; j < headerRow.length; j++) {
          final String headerText = headerRow[j].toString().toLowerCase().trim();
          if (headerText.contains('wind speed (km/h)')) {
            columnsToSkip.add(j);
          }
          if (headerRow[j].toString().trim() == 'Fan (sec)') {
            fanSecIndex = j;
          }
        }

        for (int i = 6; i < csvRows.length; i++) {
          final row = csvRows[i];

          if (fanSecIndex != null && fanSecIndex < row.length) {
            totalFanSeconds += double.tryParse(row[fanSecIndex].toString()) ?? 0;
          }
          if (cool1Idx != -1 && cool1Idx < row.length) {
            totalCool1Seconds += double.tryParse(row[cool1Idx].toString()) ?? 0;
          }
          if (cool2Idx != -1 && cool2Idx < row.length) {
            totalCool2Seconds += double.tryParse(row[cool2Idx].toString()) ?? 0;
          }
          if (heat1Idx != -1 && heat1Idx < row.length) {
            totalHeat1Seconds += double.tryParse(row[heat1Idx].toString()) ?? 0;
          }
          if (heat2Idx != -1 && heat2Idx < row.length) {
            totalHeat2Seconds += double.tryParse(row[heat2Idx].toString()) ?? 0;
          }
          if (aux1Idx != -1 && aux1Idx < row.length) {
            totalAux1Seconds += double.tryParse(row[aux1Idx].toString()) ?? 0;
          }
          if (aux2Idx != -1 && aux2Idx < row.length) {
            totalAux2Seconds += double.tryParse(row[aux2Idx].toString()) ?? 0;
          }
        }

        if (fanSecIndex != null) _totalFanHours = totalFanSeconds / 3600;
        if (cool1Idx != -1) _totalCool1Hours = totalCool1Seconds / 3600;
        if (cool2Idx != -1) _totalCool2Hours = totalCool2Seconds / 3600;
        if (heat1Idx != -1) _totalHeat1Hours = totalHeat1Seconds / 3600;
        if (heat2Idx != -1) _totalHeat2Hours = totalHeat2Seconds / 3600;
        if (aux1Idx != -1) _totalAux1Hours = totalAux1Seconds / 3600;
        if (aux2Idx != -1) _totalAux2Hours = totalAux2Seconds / 3600;
      }

      int maxColumns = 0;
      double maxHeaderLength = 0;
      bool hasLongCalendarContent = false;

      for (int i = 0; i < csvRows.length; i++) {
        final rowData = csvRows[i];
        int targetCol = 1;

        for (int j = 0; j < rowData.length; j++) {
          if (columnsToSkip.contains(j)) continue;
          final String cellText = rowData[j].toString();

          if (i == 5) {
            String? hexColor;
            if (cellText.contains('Cool Set Temp')) {
              hexColor = '#496daf';
            } else if (cellText.contains('Heat Set Temp')) {
              hexColor = '#fe4949';
            } else if (cellText.contains('Current Temp') ||
                cellText.contains('Thermostat Temperature')) {
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
              final double length = cellText.length.toDouble();
              if (length > maxHeaderLength) maxHeaderLength = length;
            } else {
              final cellRange = sheet.getRangeByIndex(i + 1, targetCol);
              cellRange.setText(cellText);
              if (hexColor != null) cellRange.cellStyle.backColor = hexColor;
            }
          } else {
            final cellRange = sheet.getRangeByIndex(i + 1, targetCol);
            final double? numericValue = double.tryParse(cellText);

            if (numericValue != null) {
              cellRange.setNumber(numericValue);
            } else {
              cellRange.setText(cellText);
            }

            if (i >= 6) {
              if (targetCol == 5 && cellText.length > 4) {
                hasLongCalendarContent = true;
              }
            }
          }

          if (targetCol > maxColumns) maxColumns = targetCol;
          targetCol++;
        }
      }

      final double calculatedHeight = (maxHeaderLength * 3.2).clamp(20.0, 120.0);
      sheet.setRowHeightInPixels(6, calculatedHeight);

      for (int col = 1; col <= maxColumns; col++) {
        sheet.autoFitColumn(col);
        final xlsio.Range colRange = sheet.getRangeByIndex(6, col);
        final String headerText = colRange.getText() ?? '';
        if (headerText.contains('Calendar Event') && hasLongCalendarContent) {
          final double autoWidth = colRange.columnWidth;
          colRange.columnWidth = autoWidth / 2;
        }
      }

      sheet.getRangeByIndex(1, 4).cellStyle.backColor = '#ffff00';
      if (csvRows.length >= 7) {
        sheet.getRangeByIndex(7, 1).freezePanes();
      }

      final List<int> outBytes = workbook.saveAsStream();
      final blob = html.Blob(
        [outBytes],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      final url = html.Url.createObjectUrlFromBlob(blob);

      final String baseName = fileName.replaceAll(RegExp(r'\.(csv|xlsx)$', caseSensitive: false), '');
      final String downloadName = '$baseName(new).xlsx';

      html.AnchorElement(href: url)
        ..setAttribute('download', downloadName)
        ..click();
      html.Url.revokeObjectUrl(url);

      await analytics.logEvent(name: 'process_file_success');

      setState(() {
        _rebootCount = rebootCounter;
        _rebootDetails = currentRebootDetails;
        _statusMessage = 'Conversion Successful!';
      });

      await Future.delayed(const Duration(seconds: 3));

      setState(() {
        _statusMessage = 'Drag & Drop CSV Here \nor\n Click to Upload';
        _isDragging = false;
        _isProcessing = false;
      });
    } catch (e) {
      await analytics.logEvent(
        name: 'process_file_error',
        parameters: {'file_name': fileName, 'error': e.toString()},
      );
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
    } finally {
      workbook?.dispose();
      setState(() {
        _isProcessing = false;
      });
    }
  }

  bool _isUpToDate(String local, String remote) {
    try {
      final List<int> localParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final List<int> remoteParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final int maxLength = localParts.length > remoteParts.length ? localParts.length : remoteParts.length;

      for (int i = 0; i < maxLength; i++) {
        final int localSegment = i < localParts.length ? localParts[i] : 0;
        final int remoteSegment = i < remoteParts.length ? remoteParts[i] : 0;
        if (localSegment > remoteSegment) return true;
        if (localSegment < remoteSegment) return false;
      }
      return true;
    } catch (_) {
      return local == remote;
    }
  }

  @override
  Widget build(BuildContext context) {
    String displayVersionText = 'Version ${widget.version}';
    Color versionColor = Colors.blueGrey.shade300;
    FontWeight versionWeight = FontWeight.w400;

    if (_latestVersion != null) {
      final bool upToDate = _isUpToDate(widget.version, _latestVersion!);
      if (upToDate) {
        displayVersionText = 'Version ${widget.version} (latest)';
        versionColor = Colors.green.shade600;
      } else {
        displayVersionText = 'Version ${widget.version} (Click to update)';
        versionColor = Colors.redAccent;
        versionWeight = FontWeight.w600;
      }
    }

    return Scaffold(
      appBar: const ConsistentAppBar(currentPage: 'Home'),
      backgroundColor: const Color(0xFFF8F9FB),
      body: Stack(
        children: [
          SingleChildScrollView(
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
                          cursor: (_latestVersion != null && !_isUpToDate(widget.version, _latestVersion!))
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.basic,
                          child: GestureDetector(
                            onTap: () {
                              if (_latestVersion != null && !_isUpToDate(widget.version, _latestVersion!)) {
                                html.window.location.reload();
                              }
                            },
                            child: Text(
                              displayVersionText,
                              style: TextStyle(
                                color: versionColor,
                                fontSize: 12,
                                fontWeight: versionWeight,
                                decoration: (_latestVersion != null &&
                                        !_isUpToDate(widget.version, _latestVersion!))
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SectionCard(
                      title: 'About CSV Analyzer',
                      children: [
                        Text(
                          'A web app designed to transform raw ecobee thermostat system monitoring data into a clear and readable report for faster and more accurate diagnostics.',
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
                      onDragEntered: (_) => setState(() => _isDragging = true),
                      onDragExited: (_) => setState(() => _isDragging = false),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _pickFile,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 200,
                            width: 420,
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
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_serialNumber != null)
                      ExpandableSectionCard(
                        maxWidth: 700,
                        title: 'Thermostat Report Summary',
                        titleBackgroundColor: Colors.grey.shade300,
                        titleColor: Colors.black,
                        initiallyExpanded: true,
                        children: [
                          _summaryBox('Thermostat Serial Number: $_serialNumber'),
                          _summaryBox('Thermostat Name: $_thermostatName'),
                          if (_startDate != null) _summaryBox('Start Date: $_startDate'),
                          if (_endDate != null) _summaryBox('End Date: $_endDate'),
                        ],
                      ),
                    if (_serialNumber != null)
                      ExpandableSectionCard(
                        maxWidth: 700,
                        title: 'Overall Stats',
                        titleBackgroundColor: Colors.blueGrey.shade100,
                        titleColor: Colors.black,
                        initiallyExpanded: true,
                        children: [
                          if (_totalFanHours != null)
                            _summaryBox(
                              'Total Fan Runtime: ${(_totalFanHours! * 3600).toInt()} seconds (${_totalFanHours!.toStringAsFixed(2)} hours)',
                              color: const Color(0xFFC6E0B4),
                            ),
                          if (_totalCool1Hours != null)
                            _summaryBox(
                              'Cool (Stage 1): ${(_totalCool1Hours! * 3600).toInt()} seconds (${_totalCool1Hours!.toStringAsFixed(2)} hours)',
                              color: const Color(0xFFCADFF2),
                            ),
                          if (_totalCool2Hours != null)
                            _summaryBox(
                              'Cool (Stage 2): ${(_totalCool2Hours! * 3600).toInt()} seconds (${_totalCool2Hours!.toStringAsFixed(2)} hours)',
                              color: const Color(0xFFCADFF2),
                            ),
                          if (_totalHeat1Hours != null)
                            _summaryBox(
                              'Heat (Stage 1): ${(_totalHeat1Hours! * 3600).toInt()} seconds (${_totalHeat1Hours!.toStringAsFixed(2)} hours)',
                              color: const Color(0xFFFFE5E8),
                            ),
                          if (_totalHeat2Hours != null)
                            _summaryBox(
                              'Heat (Stage 2): ${(_totalHeat2Hours! * 3600).toInt()} seconds (${_totalHeat2Hours!.toStringAsFixed(2)} hours)',
                              color: const Color(0xFFFFE5E8),
                            ),
                          if (_totalAux1Hours != null)
                            _summaryBox(
                              'Aux (Heat 1): ${(_totalAux1Hours! * 3600).toInt()} seconds (${_totalAux1Hours!.toStringAsFixed(2)} hours)',
                              color: const Color(0xFFFFE5E8),
                            ),
                          if (_totalAux2Hours != null)
                            _summaryBox(
                              'Aux (Heat 2): ${(_totalAux2Hours! * 3600).toInt()} seconds (${_totalAux2Hours!.toStringAsFixed(2)} hours)',
                              color: const Color(0xFFFFE5E8),
                            ),
                          if (_rebootCount != null)
                            _summaryBox(
                              'Total Reboots: $_rebootCount',
                              color: const Color(0xFFFFE5E8),
                            ),
                        ],
                      ),
                    if (_serialNumber != null)
                      ExpandableSectionCard(
                        maxWidth: 700,
                        title: 'Reboot Indicators Table (${_rebootCount ?? 0})',
                        titleColor: Colors.black,
                        titleBackgroundColor: const Color(0xFFEF5350),
                        initiallyExpanded: false,
                        children: [
                          if (_rebootDetails.isNotEmpty)
                            Align(
                              alignment: Alignment.center,
                              child: Table(
                                border: TableBorder.all(
                                  color: Colors.grey.shade300,
                                  width: 1,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                columnWidths: const {
                                  0: FixedColumnWidth(60),
                                  1: FixedColumnWidth(110),
                                  2: FixedColumnWidth(110),
                                },
                                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(color: Colors.grey.shade100),
                                    children: [
                                      _tableHeader('#'),
                                      _tableHeader('Start Date'),
                                      _tableHeader('Start Time'),
                                    ],
                                  ),
                                  ..._rebootDetails.asMap().entries.map((entry) {
                                    final int index = entry.key;
                                    final String detail = entry.value;
                                    final List<String> parts = detail.split(' ');
                                    final String rebootStartDate = parts.isNotEmpty ? parts[0] : detail;
                                    final String rebootStartTime = parts.length > 1 ? parts[1] : '';
                                    return TableRow(
                                      children: [
                                        _tableCell('${index + 1}'),
                                        _tableCell(rebootStartDate),
                                        _tableCell(rebootStartTime),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            )
                          else
                            const Text('No Issues Here.'),
                        ],
                      ),
                    const SizedBox(height: 200),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: _isChatOpen
                ? SupportChatWidget(onClose: () => setState(() => _isChatOpen = false))
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

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
      ),
    );
  }

  Widget _tableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}

class SupportChatWidget extends StatefulWidget {
  const SupportChatWidget({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<SupportChatWidget> createState() => _SupportChatWidgetState();
}

class _SupportChatWidgetState extends State<SupportChatWidget> {
// final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final KnowledgeBaseService _knowledgeBaseService;
  late final LocalSearchService _localSearchService;
  late final GeminiService _geminiService;

  List<KnowledgeItem> _knowledgeBase = [];
  List<SearchResult> _latestMatches = [];
  final List<ChatMessage> _messages = [
    const ChatMessage(
      role: ChatRole.assistant,
      text: 'Hi! I can answer questions using the JSON knowledge base.',
    ),
  ];

  bool _isLoading = false;
  String _status = 'Loading knowledge base...';

  @override
  void initState() {
    super.initState();
    _knowledgeBaseService = KnowledgeBaseService();
    _localSearchService = LocalSearchService();
    _geminiService = GeminiService();
    _loadKnowledgeBase();
  }

  Future<void> _loadKnowledgeBase() async {
    try {
      final items = await _knowledgeBaseService.loadKnowledgeBase();
      setState(() {
        _knowledgeBase = items;
        _status = 'Loaded ${items.length} knowledge base records from assets/data/knowledge_base.json';
      });
    } catch (e) {
      setState(() {
        _status = 'Could not load JSON asset: $e';
      });
    }
  }

  Future<void> _sendMessage() async {
    final query = _messageController.text.trim();
    if (query.isEmpty || _isLoading) return;
    const apiKey = '';
    /* final apiKey = _apiKeyController.text.trim();

    if (apiKey.isEmpty) {
      setState(() {
        _messages.add(const ChatMessage(
          role: ChatRole.assistant,
          text: 'Please paste a Gemini API key before sending a message.',
        ));
      });
      return;
    }
*/
    if (_knowledgeBase.isEmpty) {
      setState(() {
        _messages.add(const ChatMessage(
          role: ChatRole.assistant,
          text: 'The JSON knowledge base is still empty or failed to load.',
        ));
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _messages.add(ChatMessage(role: ChatRole.user, text: query));
    });

    _messageController.clear();

    final matches = _localSearchService.retrieveTopMatches(_knowledgeBase, query, limit: 5);

    setState(() {
      _latestMatches = matches;
      _status = '${matches.length} local match(es) selected from ${_knowledgeBase.length} JSON records. Only those matches are sent to Gemini.';
    });

    try {
      final reply = await _geminiService.generateGroundedReply(
        apiKey: apiKey,
        userQuery: query,
        matches: matches,
      );

      setState(() {
        _messages.add(ChatMessage(role: ChatRole.assistant, text: reply));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(role: ChatRole.assistant, text: 'Error while calling Gemini: $e'));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 140,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 14,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 390,
        height: 640,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF0F766E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Support assistant',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'JSON-grounded answers with Gemini',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
/*                        TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Gemini API key',
                            hintText: 'Paste API key for testing',
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                          ),
                        ),
*/
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Text(
                            _status,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF4B5563),
                              height: 1.5,
                            ),
                          ),
                        ),
                        if (_latestMatches.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 86,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _latestMatches.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final result = _latestMatches[index];
                                return Container(
                                  width: 160,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFFA7F3D0)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        result.item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF065F46),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'ID: ${result.item.id} · score ${result.score}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF047857)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: ListView.separated(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isUser = message.role == ChatRole.user;
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 280),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isUser ? const Color(0xFF0F766E) : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                                  bottomRight: Radius.circular(isUser ? 4 : 16),
                                ),
                                border: isUser ? null : Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Text(
                                message.text,
                                style: TextStyle(
                                  height: 1.5,
                                  color: isUser ? Colors.white : const Color(0xFF111827),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Ask a support question...',
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _isLoading ? null : _sendMessage,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            minimumSize: const Size(58, 58),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KnowledgeBaseService {
  Future<List<KnowledgeItem>> loadKnowledgeBase() async {
    final rawJson = await rootBundle.loadString('assets/data/knowledge_base.json');

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
    if (item.tags.any((tag) => tag.toLowerCase().contains(q) || q.contains(tag.toLowerCase()))) {
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

Database context:
${context.isEmpty ? 'No matching database records were found.' : context}

User question:
$userQuery''';

    final response = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
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
