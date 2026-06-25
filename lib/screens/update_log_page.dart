import 'package:flutter/material.dart';
import '../widgets/app_bar.dart';
import '../widgets/section_card.dart';

class UpdateLogPage extends StatelessWidget {
  const UpdateLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: const ConsistentAppBar(currentPage: "log"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            // Expanded width constraint from 900 to 1200 for a wider section
            constraints: const BoxConstraints(maxWidth: 1200),
            child: SectionCard(
              title: "Application Update Log",
              children: [




                _buildVersionBlock(
                  version: "Version 2.0.2+2",
                  date: "June 20 2026",
                  changes: [
                 "Added a thermostat controller page where users can control their ecobee thermostat from this web application."],
                ),


                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Divider(color: Colors.black12, height: 1),
                ),

                _buildVersionBlock(
                  version: "Version 1.0.2+2",
                  date: "June 11 2026",
                  changes: [
                    "Initial app release",
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Divider(color: Colors.black12, height: 1),
                ),


              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Helper widget to cleanly format version rows inside the single card view
  Widget _buildVersionBlock({
    required String version,
    required String date,
    required List<String> changes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              version,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172538), // Aligned to your AppBar theme color
              ),
            ),
            Text(
              date,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: changes.map((change) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "• ",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      change,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}