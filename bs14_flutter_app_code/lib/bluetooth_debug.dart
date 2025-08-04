import 'package:flutter/material.dart';
import 'dart:async';
import 'bluetooth_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothDebugScreen extends StatefulWidget {
  const BluetoothDebugScreen({super.key});

  @override
  State<BluetoothDebugScreen> createState() => _BluetoothDebugScreenState();
}

class _BluetoothDebugScreenState extends State<BluetoothDebugScreen> {
  final BluetoothService _bluetoothService = BluetoothService();
  List<fbp.BluetoothDevice> _devices = [];
  bool _isScanning = false;
  String _connectionStatus = 'Disconnected';
  String _lastStatusUpdate = 'None';
  bool _breakerState = false;
  bool _switchState = false;
  fbp.BluetoothDevice? _lastConnectedDevice;
  bool _autoReconnect = true;

  // Store our callback function so we can remove it later
  late Function(bool, bool) _debugStatusCallback;

  @override
  void initState() {
    super.initState();
    _setupStatusListener();
    _startConnectionMonitoring();
  }

  void _startConnectionMonitoring() {
    // Check connection status every 3 seconds
    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _checkConnectionStatus();
    });
  }

  void _checkConnectionStatus() {
    final isConnected = _bluetoothService.isConnected;
    print(
      "🔍 Connection check: isConnected=$isConnected, status=$_connectionStatus",
    );

    if (!isConnected && _lastConnectedDevice != null && _autoReconnect) {
      print("🔄 Connection lost, attempting to reconnect...");
      _reconnectToLastDevice();
    }

    // Update connection status display
    if (!isConnected && _connectionStatus == 'Connected') {
      setState(() {
        _connectionStatus = 'Connection Lost - Reconnecting...';
      });
    } else if (isConnected &&
        _connectionStatus != 'Connected' &&
        _connectionStatus != 'Reconnected') {
      setState(() {
        _connectionStatus = 'Connected';
      });
    }
  }

  Future<void> _reconnectToLastDevice() async {
    if (_lastConnectedDevice == null) return;

    try {
      print("🔄 Reconnecting to ${_lastConnectedDevice!.platformName}...");
      final connected = await _bluetoothService.connectToDevice(
        _lastConnectedDevice!,
      );

      setState(() {
        _connectionStatus = connected ? 'Reconnected' : 'Reconnection Failed';
      });

      if (connected) {
        print("✅ Reconnected successfully!");
        _setupStatusListener();
      }
    } catch (e) {
      print("❌ Reconnection error: $e");
    }
  }

  void _setupStatusListener() {
    print("🎧 Setting up debug status listener...");

    // Define our callback function
    _debugStatusCallback = (breakerOpen, switchUp) {
      setState(() {
        _breakerState = breakerOpen;
        _switchState = switchUp;
        _lastStatusUpdate =
            'Breaker: ${breakerOpen ? "OPEN" : "CLOSED"}, Switch: ${switchUp ? "UP" : "DOWN"} - ${DateTime.now().toLocal()}';
      });
      print("📥 Debug status update received: $_lastStatusUpdate");
    };

    // Register the callback
    _bluetoothService.listenForStatusUpdates(_debugStatusCallback);
  }

  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    try {
      print("🔍 Starting device scan...");
      final devices = await _bluetoothService.scanDevices();
      setState(() {
        _devices = devices;
        _isScanning = false;
      });
      print("✅ Scan completed. Found ${devices.length} devices");
    } catch (e) {
      print("❌ Scan error: $e");
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(fbp.BluetoothDevice device) async {
    setState(() {
      _connectionStatus = 'Connecting...';
    });

    try {
      print("🔗 Connecting to ${device.platformName}...");
      final connected = await _bluetoothService.connectToDevice(device);

      setState(() {
        _connectionStatus = connected ? 'Connected' : 'Failed to connect';
      });

      if (connected) {
        print("✅ Connected successfully!");
        _lastConnectedDevice = device; // Store for auto-reconnection
        // Re-setup the status listener after connection
        _setupStatusListener();
      } else {
        print("❌ Connection failed");
      }
    } catch (e) {
      print("❌ Connection error: $e");
      setState(() {
        _connectionStatus = 'Error: $e';
      });
    }
  }

  Future<void> _sendTestCommand() async {
    if (!_bluetoothService.isConnected) {
      print("❌ Not connected to device");
      return;
    }

    try {
      // Toggle breaker state for testing
      final newState = !_breakerState;
      print("📤 Sending test command: ${newState ? 'OPEN' : 'CLOSE'}");
      await _bluetoothService.sendBreakerCommand(newState, _switchState);
      print("✅ Command sent successfully");
    } catch (e) {
      print("❌ Error sending command: $e");
    }
  }

  Future<void> _forceReconnect() async {
    print("🔄 Force reconnecting...");

    // Disconnect first
    await _bluetoothService.disconnect();
    await Future.delayed(const Duration(seconds: 1));

    // Clear status
    setState(() {
      _connectionStatus = 'Force Reconnecting...';
    });

    if (_lastConnectedDevice != null) {
      await _connectToDevice(_lastConnectedDevice!);
    } else {
      print("❌ No last connected device to reconnect to");
    }
  }

  void _refreshStatus() {
    print("🔄 Refreshing status...");
    final isConnected = _bluetoothService.isConnected;
    setState(() {
      _connectionStatus = isConnected ? 'Connected' : 'Disconnected';
    });
    print("📊 Current connection state: $isConnected");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Debug'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection Status: $_connectionStatus',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Last Status Update: $_lastStatusUpdate'),
                    const SizedBox(height: 8),
                    Text(
                      'Current State: Breaker ${_breakerState ? "OPEN" : "CLOSED"}, Switch ${_switchState ? "UP" : "DOWN"}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Control Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isScanning ? null : _scanForDevices,
                  child: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
                ),
                ElevatedButton(
                  onPressed: _bluetoothService.isConnected
                      ? _sendTestCommand
                      : null,
                  child: const Text('Send Test Command'),
                ),
                ElevatedButton(
                  onPressed: _forceReconnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: const Text('Force Reconnect'),
                ),
                ElevatedButton(
                  onPressed: _refreshStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                  ),
                  child: const Text('Refresh Status'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Auto-reconnect toggle
            Row(
              children: [
                Switch(
                  value: _autoReconnect,
                  onChanged: (value) {
                    setState(() {
                      _autoReconnect = value;
                    });
                  },
                ),
                const SizedBox(width: 8),
                const Text('Auto-reconnect when connection drops'),
              ],
            ),

            const SizedBox(height: 16),

            // Device List
            const Text(
              'Found Devices:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _devices.isEmpty
                  ? const Center(
                      child: Text(
                        'No devices found. Tap "Scan for Devices" to start.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        final deviceName = device.platformName.isEmpty
                            ? 'Unknown Device'
                            : device.platformName;

                        // Check if this looks like our Arduino
                        final isArduino = BluetoothService.isArduinoDevice(
                          device,
                          [],
                        );

                        return Card(
                          color: isArduino ? Colors.green.shade100 : null,
                          child: ListTile(
                            title: Text(deviceName),
                            subtitle: Text(device.remoteId.toString()),
                            trailing: isArduino
                                ? const Icon(Icons.star, color: Colors.orange)
                                : null,
                            leading: Icon(
                              isArduino
                                  ? Icons.developer_board
                                  : Icons.bluetooth,
                              color: isArduino ? Colors.green : Colors.blue,
                            ),
                            onTap: () => _connectToDevice(device),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Remove our status listener before disposing
    _bluetoothService.removeStatusListener(_debugStatusCallback);
    super.dispose();
  }
}
