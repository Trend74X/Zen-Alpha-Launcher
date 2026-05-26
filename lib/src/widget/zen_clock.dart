import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Import for formatting

class ZenClock extends StatefulWidget {
  const ZenClock({super.key});

  @override
  State<ZenClock> createState() => _ZenClockState();
}

class _ZenClockState extends State<ZenClock> {
  late Timer _timer;
  String _timeString = "";

  @override
  void initState() {
    super.initState();
    _timeString = _formatDateTime(DateTime.now());
    // Update the clock every second
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _getTime());
  }

  @override
  void dispose() {
    _timer.cancel(); // Always cancel timers to prevent memory leaks
    super.dispose();
  }

  void _getTime() {
    final DateTime timeNow = DateTime.now();
    final String formattedDateTime = _formatDateTime(timeNow);
    setState(() {
      _timeString = formattedDateTime;
    });
  }

  String formatDate(DateTime dateTime) {
    // 'E' = Fri, 'd' = 5, 'MMM' = Sept
    return DateFormat('E d, MMM').format(dateTime);
  }

  String _formatDateTime(DateTime dateTime) {
    // 'HH:mm' gives 24-hour time. Use 'hh:mm' for 12-hour.
    return DateFormat('HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    return Column(
      children: [
        Text(
          DateFormat('E d, MMM').format(now),
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 18,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
          ),
        ),
        Text(
          _timeString,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 100, // Large "Zen" style
            fontWeight: FontWeight.w500, // Thin font for elegance
            letterSpacing: -5,
          ),
        ),
      ],
    );
  }
}