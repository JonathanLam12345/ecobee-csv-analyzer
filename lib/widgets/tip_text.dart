import 'package:flutter/material.dart';

class TipText extends StatelessWidget {
  final String text;
  final TextAlign textAlign;

  const TipText(
      this.text, {
        super.key,
        this.textAlign = TextAlign.left,
      });

  @override
  Widget build(BuildContext context) {
    final TextStyle separatorStyle = const TextStyle(
      fontWeight: FontWeight.bold,
      color: Color(0xFFEF5350),
      fontSize: 15,
    );

    final TextStyle normalStyle = const TextStyle(
      color: Colors.black,
      fontSize: 12,
      height: 1.4,
    );

    final TextStyle boldStyle = TextStyle(
      color: Colors.blueGrey.shade800,
      fontWeight: FontWeight.bold,
      fontSize: 12,
      height: 1.4,
    );

    final List<InlineSpan> spans = [];

    if (text.contains('|')) {
      final parts = text.split('|');

      for (int i = 0; i < parts.length; i++) {
        if (i == 0 && parts[i].trim().startsWith('Reboot #')) {
          spans.add(TextSpan(text: parts[i], style: boldStyle));
        } else {
          spans.add(TextSpan(text: parts[i], style: normalStyle));
        }

        if (i < parts.length - 1) {
          spans.add(TextSpan(text: ' | ', style: separatorStyle));
        }
      }
    } else if (text.contains(':')) {
      final colonIndex = text.indexOf(':');

      final boldPart = text.substring(0, colonIndex + 1);
      final normalPart = text.substring(colonIndex + 1);

      spans.add(TextSpan(text: boldPart, style: boldStyle));
      spans.add(TextSpan(text: normalPart, style: normalStyle));
    } else {
      spans.add(TextSpan(text: text, style: normalStyle));
    }

    final content = SelectableText.rich(
      TextSpan(children: spans),
      textAlign: textAlign,
    );

    final child = textAlign == TextAlign.center
        ? Center(child: content)
        : Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "• ",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(width: 8),
        Expanded(child: content),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: child,
    );
  }
}