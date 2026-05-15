import 'package:flutter/material.dart';

import '../main.dart';
import '../screens/how_to_use.dart';
import '../screens/privacy_policy.dart';

class ConsistentAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String currentPage;

  const ConsistentAppBar({
    super.key,
    required this.currentPage,
  });

  Widget _navButton(
      BuildContext context,
      String label,
      String pageId,
      VoidCallback onPressed,
      ) {
    final isActive = currentPage == pageId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TextButton(
        onPressed: isActive ? null : onPressed,
        style: TextButton.styleFrom(
          backgroundColor:
          isActive ? Colors.white.withOpacity(0.15) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                letterSpacing: 0.8,
                fontWeight:
                isActive ? FontWeight.bold : FontWeight.w400,
              ),
            ),
            if (isActive)
              Container(
                margin: const EdgeInsets.only(top: 4),
                height: 3,
                width: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text(
        "",
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
      elevation: 4,
      automaticallyImplyLeading: false,
      actions: [
        _navButton(context, "HOME", "Home", () {
          if (currentPage != "Home") {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        }),
        _navButton(context, "About", "Info", () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, anim1, anim2) =>
              const HowToUsePage(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        }),
        _navButton(context, "Privacy Policy", "privacy", () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, anim1, anim2) =>
              const PrivacyPolicyPage(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        }),
        const SizedBox(width: 12),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}