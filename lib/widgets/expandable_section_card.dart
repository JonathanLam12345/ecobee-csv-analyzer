import 'package:flutter/material.dart';

class ExpandableSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final double? maxWidth;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? titleColor;
  final Color? titleBackgroundColor; // [NEW] Added parameter for header background
  final bool initiallyExpanded;

  const ExpandableSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.maxWidth,
    this.backgroundColor,
    this.borderColor,
    this.titleColor,
    this.titleBackgroundColor, // [NEW] Added to constructor
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // [NEW] ClipRRect ensures the title background doesn't poke out of the rounded corners
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderColor != null ? 10 : 12),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            controlAffinity: ListTileControlAffinity.leading,

            // [NEW] Colors the header area
            collapsedBackgroundColor: titleBackgroundColor,
            backgroundColor: titleBackgroundColor,

            iconColor: titleColor ?? Colors.blueGrey,
            collapsedIconColor: titleColor ?? Colors.blueGrey,
            tilePadding: const EdgeInsets.only(left: 16, right: 24, top: 8, bottom: 8),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: titleColor ?? Colors.blueGrey,
              ),
            ),
            children: [
              // [NEW] Wraps your content to force the background back to white
              Container(
                color: backgroundColor ?? Colors.white,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 16),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}