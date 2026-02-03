import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Diagnostic page for Wi-Fi Direct troubleshooting.
/// 
/// Runs comprehensive checks on:
/// - Hardware support
/// - Wi-Fi state
/// - Location services
/// - Permissions
/// - P2P Manager initialization
class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({super.key});

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  static const platform = MethodChannel('com.rescuenet/wifi_p2p');
  
  Map<String, dynamic>? diagnosticResults;
  bool isRunning = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      isRunning = true;
      errorMessage = null;
    });
    
    try {
      final results = await platform.invokeMethod('runDiagnostics');
      setState(() {
        diagnosticResults = Map<String, dynamic>.from(results);
        isRunning = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        isRunning = false;
        errorMessage = 'Diagnostic failed: ${e.message}';
      });
    } catch (e) {
      setState(() {
        isRunning = false;
        errorMessage = 'Diagnostic failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Direct Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isRunning ? null : _runDiagnostics,
            tooltip: 'Run Again',
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (isRunning) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Running diagnostics...'),
          ],
        ),
      );
    }
    
    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _runDiagnostics,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }
    
    if (diagnosticResults == null) {
      return const Center(child: Text('No diagnostics run yet'));
    }
    
    return _buildDiagnosticResults(theme);
  }

  Widget _buildDiagnosticResults(ThemeData theme) {
    final allPassed = diagnosticResults!.values.every(
      (result) => result['passed'] == true
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary Card
        Card(
          color: allPassed 
            ? Colors.green.withOpacity(0.1) 
            : Colors.red.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  allPassed ? Icons.check_circle : Icons.error,
                  size: 64,
                  color: allPassed ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  allPassed ? 'ALL CHECKS PASSED' : 'ISSUES FOUND',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: allPassed ? Colors.green[800] : Colors.red[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  allPassed
                      ? 'Wi-Fi Direct should work on this device'
                      : 'Please fix the issues below',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        Text(
          'Diagnostic Results',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        // Individual Checks
        ...diagnosticResults!.entries.map((entry) {
          final checkName = entry.key;
          final result = entry.value as Map;
          final passed = result['passed'] as bool;
          
          return _buildCheckCard(
            theme,
            checkName,
            passed,
            result['issue'] as String? ?? '',
            result['solution'] as String? ?? '',
          );
        }),
        
        const SizedBox(height: 24),
        
        // Test Button
        if (allPassed)
          ElevatedButton.icon(
            onPressed: _testServiceRegistration,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Test Service Registration'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
      ],
    );
  }

  Widget _buildCheckCard(
    ThemeData theme,
    String name, 
    bool passed, 
    String issue, 
    String solution,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          passed ? Icons.check_circle : Icons.error,
          color: passed ? Colors.green : Colors.red,
        ),
        title: Text(
          _formatCheckName(name),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          passed ? 'OK' : issue,
          style: TextStyle(
            color: passed ? Colors.green : Colors.red,
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: passed
            ? []
            : [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.red.withOpacity(0.05),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber, 
                            size: 16, 
                            color: Colors.red[700]
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Problem',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(issue),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, 
                            size: 16, 
                            color: Colors.blue[700]
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Solution',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(solution),
                    ],
                  ),
                ),
              ],
      ),
    );
  }

  String _formatCheckName(String name) {
    switch (name) {
      case 'hardware':
        return 'Hardware Support';
      case 'wifi_enabled':
        return 'Wi-Fi Status';
      case 'location_enabled':
        return 'Location Services';
      case 'permissions':
        return 'Permissions';
      case 'p2p_manager':
        return 'Wi-Fi P2P Manager';
      default:
        return name.replaceAll('_', ' ').toUpperCase();
    }
  }

  Future<void> _testServiceRegistration() async {
    try {
      final result = await platform.invokeMethod('startBroadcasting', {
        'nodeId': 'DIAG-${DateTime.now().millisecondsSinceEpoch}',
        'metadata': {
          'test': 'true',
          'time': DateTime.now().toIso8601String(),
        },
      });
      
      if (!mounted) return;
      
      final success = result['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
            ? '✅ Service registered successfully!' 
            : '❌ Registration failed: ${result['error']}'
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
