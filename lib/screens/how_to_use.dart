import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_bar.dart';
import '../widgets/section_card.dart';
import '../widgets/tip_text.dart';

class HowToUsePage extends StatelessWidget {
  const HowToUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ConsistentAppBar(currentPage:"Info"),

      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SectionCard(
                  title: "User Tips & How to Use",
                  children: [
                    TipText(
                      "Upload your .csv Temperature Report by dragging it into the box above or clicking the box to browse the .csv file.",
                    ),
                    TipText(
                      "To locate your .csv file more easily, sort your folder by 'Date Modified' to see your most recent downloads first.",
                    ),
                    TipText(
                      "Please note the web app saves the report as a .xlsx file instead of a .csv file.\nTo have future .xlsx reports open automatically after processing, right-click the .xlsx file in Chrome's 'Recent Download History' and select 'Always open files of this type'.\nYou can also disable this setting for .csv files to prevent the unformatted data from opening automatically.",
                    ),
                    TipText(
                      "Please reach out to Jonathan Lam to report any issues or to provide feedback.",
                    ),
                  ],
                ),
              ),



              const SizedBox(height: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SectionCard(
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
