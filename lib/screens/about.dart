// import 'dart:convert';
// import 'dart:typed_data';
//
// import 'dart:html' as html;
// import 'package:flutter/material.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_analytics/firebase_analytics.dart';
// import 'package:desktop_drop/desktop_drop.dart';
// import 'package:flutter/services.dart';
// import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
// import 'package:csv/csv.dart';
// import 'package:package_info_plus/package_info_plus.dart';
// import 'package:firebase_database/firebase_database.dart';
//
//
// class AboutPage extends StatelessWidget {
//   const AboutPage({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF8F9FB),
//       appBar: _buildConsistentAppBar(context, "About"),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
//         child: Center(
//           child: ConstrainedBox(
//             constraints: const BoxConstraints(maxWidth: 900),
//             child: _buildSectionCard(
//               title: "About ecobee CSV Analyzer",
//               children: [
//                 const Text(
//                   "This tool was developed to streamline the analysis of ecobee thermostat data. "
//                       "By converting raw CSV exports into formatted Excel files, it highlights key "
//                       "system behaviors such as stage runtimes and temperature setpoints.",
//                   style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
//                 ),
//                 const SizedBox(height: 20),
//                 _buildTip("Automated formatting for Heat/Cool stages [cite: 207, 209]"),
//                 _buildTip("Visual indicators for thermostat system modes [cite: 213-224]"),
//                 _buildTip("Runtime summation for Fan performance [cite: 186-189]"),
//                 const SizedBox(height: 20),
//                 const Divider(),
//                 const SizedBox(height: 10),
//                 const Text(
//                   "Developer: Jonathan Lam",
//                   style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }