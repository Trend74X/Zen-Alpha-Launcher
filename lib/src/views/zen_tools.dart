import 'package:flutter/material.dart';

class ZenToolsPage extends StatefulWidget {
  const ZenToolsPage({super.key});

  @override
  State<ZenToolsPage> createState() => _ZenToolsPageState();
}

class _ZenToolsPageState extends State<ZenToolsPage> {
  bool isGrayscale       = true;
  bool hideNotifications = false;
  bool appTimers         = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: Padding(
        padding: const EdgeInsets.symmetric( horizontal: 16.0, vertical: 16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'ZEN\nCONTROL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  height: 0.9,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ENVIRONMENTAL ARCHITECTURE',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 60),
          
              // Settings List
              _buildToggleSetting('Grayscale Mode', 'Strip all chroma from the interface.', isGrayscale, (newValue) { setState(() => isGrayscale = newValue);}),
              _buildToggleSetting('Hide All Notifications', 'Suppress every external interruption.', hideNotifications, (newValue) { setState(() => hideNotifications = newValue);}),
              _buildToggleSetting('App Timers', 'Hard-lock distracting applications.', appTimers, (newValue) { setState(() => appTimers = newValue);}),
          
              const SizedBox(height: 40),
          
              // Bedtime Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bedtime', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Circadian alignment\nprotocol.', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('STATUS', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text('DARKNESS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
              
              const SizedBox(height: 30),
              
              // Timeline/Slider Placeholder
              const Divider(color: Colors.white, thickness: 2, endIndent: 200),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _timeLabel('MIDNIGHT'),
                  _timeLabel('7 AM'),
                  _timeLabel('10 PM'),
                ],
              ),
              
              const SizedBox(height: 40),
              
              // Bottom Stats
              Row(
                children: [
                  _buildStat('INTENSITY', 'TOTAL BLACKOUT'),
                  const SizedBox(width: 40),
                  _buildStat('DURATION', '09:00:00'),
                ],
              ),
      
              SizedBox(height: 120.0)
          
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleSetting(String title, String subtitle, bool currentValue, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Text Labels
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          
          // The Interactive Switch
          GestureDetector(
            onTap: () => onChanged(!currentValue), // Toggle the value on click
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200), // Smooth transition
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: currentValue ? Colors.white : Colors.grey[700]!, 
                  width: 2,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: currentValue ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  color: currentValue ? Colors.white : Colors.grey[800],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeLabel(String label) => Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold));

  Widget _buildStat(String label, String value) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey, width: 1))
      ),
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}