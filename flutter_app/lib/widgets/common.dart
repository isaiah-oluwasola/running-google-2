import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Same as showToast() in index.html.
void showToast(String message, {bool error = false}) {
  final messenger = messengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 2500),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.danger : AppColors.accentDark,
    ));
}

class Avatar extends StatelessWidget {
  final String letter;
  final double size;
  final bool group;
  final bool online;

  const Avatar({super.key, required this.letter, this.size = 44, this.group = false, this.online = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: group
                  ? const [Color(0xFF6C8CFF), Color(0xFF3B5BDB)]
                  : const [AppColors.accentDark, AppColors.accent],
            ),
          ),
          child: group
              ? Icon(Icons.groups, color: Colors.white, size: size * 0.5)
              : Text(
                  letter,
                  style: TextStyle(
                    color: AppColors.onAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.4,
                  ),
                ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class ImageBubble extends StatelessWidget {
  final Uint8List bytes;
  const ImageBubble({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, fit: BoxFit.contain),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textFaint),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDim)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textFaint)),
          ],
        ),
      ),
    );
  }
}

String formatRelative(DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${ts.day}/${ts.month}/${ts.year}';
}

String formatClock(DateTime ts) {
  final h = ts.hour.toString().padLeft(2, '0');
  final m = ts.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

final RegExp usernamePattern = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
final RegExp emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
