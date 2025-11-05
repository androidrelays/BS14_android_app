import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final String initialSense;
  final Function(String) onSenseChanged;
  const SettingsScreen({
    Key? key,
    required this.initialSense,
    required this.onSenseChanged,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _selectedSense;

  @override
  void initState() {
    super.initState();
    _selectedSense = widget.initialSense;
  }

  Future<void> _saveSense(String sense) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sense_mode', sense);
    widget.onSenseChanged(sense);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Sense Mode:', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: _selectedSense,
              items: const [
                DropdownMenuItem(value: 'A', child: Text('Sense A')),
                DropdownMenuItem(value: 'B', child: Text('Sense B')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedSense = value);
                  _saveSense(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
