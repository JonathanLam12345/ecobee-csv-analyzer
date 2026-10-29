import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

import '../widgets/app_bar.dart';
import '../widgets/section_card.dart';
import '../widgets/tip_text.dart';


class HowToUsePage extends StatefulWidget {
  const HowToUsePage({super.key});

  @override
  State<HowToUsePage> createState() => _HowToUsePageState();
}

class _HowToUsePageState extends State<HowToUsePage> {
 // late final YoutubePlayerController _controller;
  static const String _viewId = 'youtube-tutorial-iframe';
  static bool _isRegistered = false;


  @override
  void initState() {
    super.initState();
    _registerIframe();
  }

  void _registerIframe() {
    if (_isRegistered) return;

    // Register the native HTML iframe view factory for Flutter Web
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      _viewId,
          (int viewId) {
        final html.IFrameElement iframe = html.IFrameElement()
          ..src = 'https://www.youtube.com/embed/ATJamhOSgAc'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true;
        return iframe;
      },
    );
    _isRegistered = true;
  }

  @override
  void dispose() {
   // _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: const ConsistentAppBar(currentPage: "Info"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: SectionCard(
                  title: "User Tips & How to Use",
                  children: [
                    TipText(
                      "Upload your ecobee temperature report .csv file by dragging it into the box above or clicking the box to browse the .csv file.",
                    ),
                    TipText(
                      "To locate your .csv file more easily on your computer, sort the folder where you normally save your.csv files by 'Date Modified' and 'Descending' to see your most recent downloads first.",
                    ),
                    TipText(
                      "Please note the web app saves the report as a .xlsx file instead of a .csv file.\nTo have future .xlsx reports open automatically after processing, right-click the .xlsx file in your Google Chrome's 'Recent Download History' and select 'Always open files of this type'.\nYou can also disable this setting for .csv files to prevent the unformatted data from opening automatically.",
                    ),
                    TipText(
                        "For added convenience, instead of saving this web app as a bookmark in your browser, you can use your Google Chrome to \"Install page as app\" so it can be placed directly on your computer’s taskbar."),
                    TipText(
                      "Please reach out to Jonathan Lam to report any issues or to provide feedback.",
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SectionCard(
                  title: "Video Tutorial",
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: const HtmlElementView(viewType: _viewId),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }
}