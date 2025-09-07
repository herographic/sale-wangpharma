// lib/screens/placeholder_screen.dart

import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  final String pageTitle;
  const PlaceholderScreen({super.key, required this.pageTitle});

  @override
  Widget build(BuildContext context) {
    // The content is wrapped in a container to make the background transparent
    // so the gradient from MainScreen can show through.
    return Container(
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction, color: Colors.white.withOpacity(0.8), size: 80),
            const SizedBox(height: 20),
            Text(
              'หน้า "$pageTitle" อยู่ระหว่างการพัฒนา',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
