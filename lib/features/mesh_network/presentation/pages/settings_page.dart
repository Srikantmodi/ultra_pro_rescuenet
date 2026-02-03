import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Settings page.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _relayEnabled = true;
  bool _discoveryEnabled = true;
  bool _highAccuracyGps = false;
  bool _debugMode = false;
  double _batteryThreshold = 20;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Network', [
            _buildSwitch(
              'Auto Relay',
              'Automatically relay packets for other nodes',
              _relayEnabled,
              (v) => setState(() => _relayEnabled = v),
            ),
            _buildSwitch(
              'Auto Discovery',
              'Continuously discover nearby nodes',
              _discoveryEnabled,
              (v) => setState(() => _discoveryEnabled = v),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Location', [
            _buildSwitch(
              'High Accuracy GPS',
              'Use GPS for precise location (uses more battery)',
              _highAccuracyGps,
              (v) => setState(() => _highAccuracyGps = v),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Power', [
            _buildSlider(
              'Battery Threshold',
              'Stop relaying when battery below ${_batteryThreshold.toInt()}%',
              _batteryThreshold,
              (v) => setState(() => _batteryThreshold = v),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Developer', [
            _buildSwitch(
              'Debug Mode',
              'Show debug information and logs',
              _debugMode,
              (v) => setState(() => _debugMode = v),
            ),
            _buildAction(
              'Clear Cache',
              'Remove all cached data',
              Icons.delete_outline,
              () => _showClearCacheDialog(),
            ),
            _buildAction(
              'Export Logs',
              'Export debug logs to file',
              Icons.download,
              () {},
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('About', [
            _buildInfo('Version', '1.0.0'),
            _buildInfo('Build', '1'),
            _buildInfo('Node ID', 'Loading...'),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSwitch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[500])),
      value: value,
      onChanged: onChanged,
      activeColor: Colors.cyan,
    );
  }

  Widget _buildSlider(
    String title,
    String subtitle,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          Slider(
            value: value,
            min: 5,
            max: 50,
            divisions: 9,
            label: '${value.toInt()}%',
            onChanged: onChanged,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildAction(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[500])),
      trailing: Icon(icon, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white)),
          Text(value, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Clear Cache', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will remove all cached packets and seen packet history. Are you sure?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
