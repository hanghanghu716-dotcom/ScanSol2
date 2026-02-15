import 'package:flutter/material.dart';

class ToastUtils {
  static void show(BuildContext context, String message, {bool isError = false, bool isSuccess = false}) {
    Color bgColor = Colors.black87;
    IconData icon = Icons.info_outline;

    if (isError) {
      bgColor = const Color(0xFFD32F2F);
      icon = Icons.error_outline;
    } else if (isSuccess) {
      bgColor = const Color(0xFF2E7D32);
      icon = Icons.check_circle_outline;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        elevation: 4,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}