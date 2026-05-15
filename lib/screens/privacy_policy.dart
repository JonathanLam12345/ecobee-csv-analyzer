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

import '../widgets/app_bar.dart';
import '../widgets/section_card.dart';
import '../widgets/tip_text.dart';


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
      appBar: ConsistentAppBar(currentPage:"privacy"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SectionCard(
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
