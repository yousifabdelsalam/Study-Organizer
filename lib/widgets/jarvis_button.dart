import 'package:flutter/material.dart';

enum JarvisButtonState { idle, recording, processing, speaking }

class JarvisButton extends StatelessWidget {
  final JarvisButtonState state;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordEnd;

  const JarvisButton({super.key, required this.state, required this.onRecordStart, required this.onRecordEnd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onRecordStart(),
      onLongPressEnd: (_) => onRecordEnd(),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        width: 100, height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: state == JarvisButtonState.recording ? Colors.redAccent : Color(0xFF6C63FF),
          boxShadow: [BoxShadow(color: Color(0xFF6C63FF).withOpacity(0.5), blurRadius: 20, spreadRadius: 5)],
        ),
        child: Icon(state == JarvisButtonState.recording ? Icons.mic : Icons.bolt, color: Colors.white, size: 40),
      ),
    );
  }
}