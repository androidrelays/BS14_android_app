import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'bluetooth_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breaker Control',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: const BreakerControlScreen(),
    );
  }
}

class BreakerControlScreen extends StatefulWidget {
  const BreakerControlScreen({super.key});

  @override
  State<BreakerControlScreen> createState() => _BreakerControlScreenState();
}

class _BreakerControlScreenState extends State<BreakerControlScreen> {
  bool switchToggled = true; // Initialize as UP position (large toggle at top)
  bool breakerOpen = true; // Initialize as OPEN
  final BluetoothService _bluetoothService = BluetoothService();
  bool _isBluetoothConnected = false;
  String _connectionStatus = 'Disconnected';

  @override
  void initState() {
    super.initState();
    // Allow both orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Listen for status updates from Arduino
    _bluetoothService.listenForStatusUpdates((breakerOpen, switchUp) {
      setState(() {
        // Update local state with Arduino status
        this.breakerOpen = breakerOpen;
        switchToggled = switchUp;
      });
    });
  }

  @override
  void dispose() {
    // Disconnect Bluetooth when leaving
    _bluetoothService.disconnect();
    // Reset to portrait when leaving the screen
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void setBreakerState(bool open) {
    setState(() {
      // Always allow opening
      // Only allow closing if switch is up (true = large toggle at top)
      if (open) {
        breakerOpen = true; // Always allow opening
      } else if (switchToggled) {
        // Switch up is true (large toggle at top)
        breakerOpen = false; // Only allow closing if switch is up
      }
      // If switch is down and trying to close, do nothing
    });

    // Send command to Arduino via Bluetooth
    _sendArduinoCommand();
  }

  void _sendArduinoCommand() async {
    if (_bluetoothService.isConnected) {
      await _bluetoothService.sendBreakerCommand(breakerOpen, switchToggled);
    }
  }

  void _showBluetoothDialog() async {
    try {
      print("Bluetooth dialog requested");

      // Show loading dialog first
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            title: Text('Searching for devices...'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Please wait'),
              ],
            ),
          );
        },
      );

      var devices = await _bluetoothService.getPairedDevices();
      print("Found ${devices.length} devices");

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (!mounted) return;

      if (devices.isEmpty) {
        // Show no devices found dialog
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('No Devices Found'),
              content: const Text(
                'No Bluetooth devices found. Please ensure:\n\n1. Bluetooth is enabled\n2. Your Arduino is powered on\n3. Your Arduino is in pairing mode',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showBluetoothDialog(); // Try again
                  },
                  child: const Text('Try Again'),
                ),
              ],
            );
          },
        );
        return;
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Connect to Arduino'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  String deviceName = devices[index].platformName.isNotEmpty
                      ? devices[index].platformName
                      : 'Unknown Device';
                  String deviceId = devices[index].remoteId.toString();
                  bool isArduinoDevice = BluetoothService.isArduinoDevice(
                    devices[index],
                    [],
                  );

                  return ListTile(
                    leading: Icon(
                      isArduinoDevice
                          ? Icons.electrical_services
                          : Icons.bluetooth,
                      color: isArduinoDevice ? Colors.green : null,
                    ),
                    title: Text(
                      isArduinoDevice
                          ? "🎯 $deviceName (Arduino Breaker)"
                          : deviceName,
                      style: TextStyle(
                        fontWeight: isArduinoDevice
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isArduinoDevice ? Colors.green : null,
                      ),
                    ),
                    subtitle: Text(deviceId),
                    tileColor: isArduinoDevice
                        ? Colors.green.withOpacity(0.1)
                        : null,
                    onTap: () async {
                      print("🎯🎯🎯 USER TAPPED ON DEVICE: $deviceName 🎯🎯🎯");
                      print("📱 Starting connection process...");

                      // Store the dialog context before closing
                      final dialogContext = context;
                      Navigator.of(dialogContext).pop();

                      // Show connecting dialog and store its context
                      BuildContext? connectingDialogContext;
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext context) {
                          connectingDialogContext = context;
                          return const AlertDialog(
                            title: Text('Connecting...'),
                            content: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(width: 20),
                                Text('Please wait'),
                              ],
                            ),
                          );
                        },
                      );

                      print("🔗 Calling BluetoothService.connectToDevice...");
                      bool connected = await _bluetoothService.connectToDevice(
                        devices[index],
                      );
                      print("🔗 Connection result: $connected");

                      // Close connecting dialog safely
                      if (mounted && connectingDialogContext != null) {
                        Navigator.of(connectingDialogContext!).pop();
                      }

                      setState(() {
                        _isBluetoothConnected = connected;
                        _connectionStatus = connected
                            ? 'Connected to ${devices[index].platformName.isNotEmpty ? devices[index].platformName : 'Device'}'
                            : 'Failed to connect';
                      });

                      // Show result message
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              connected
                                  ? 'Connected successfully!'
                                  : 'Connection failed',
                            ),
                            backgroundColor: connected
                                ? Colors.green
                                : Colors.red,
                          ),
                        );

                        // If connected, send current state to Arduino
                        if (connected) {
                          _sendArduinoCommand();
                        }
                      }
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print("Error in Bluetooth dialog: $e");
      // Close any open dialogs
      if (mounted) Navigator.of(context).pop();

      // Show error dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Bluetooth Error'),
              content: Text(
                'Error: $e\n\nPlease check that Bluetooth is enabled and try again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Enforce rule: if switch is down, breaker must be open
    if (!switchToggled && !breakerOpen) {
      // switchToggled false = down position (small toggle at bottom)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          breakerOpen = true;
        });
      });
    }

    final Color openColor = Colors.green.shade700;
    final Color openInactive = Colors.green.shade900;
    final Color closeColor = Colors.red.shade700;
    final Color closeInactive = const Color(0xFF5D1A1A); // Much darker red
    final Color bgColor = breakerOpen ? openColor : closeColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          color: bgColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bluetooth connection status at the top
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isBluetoothConnected
                      ? Colors.green.shade100
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isBluetoothConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      color: _isBluetoothConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _connectionStatus,
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _showBluetoothDialog,
                      child: const Text(
                        'Connect to Arduino',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Switch container
              Container(
                width: 200,
                height: 300,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.yellow,
                  border: Border.all(width: 5, color: Colors.black),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "UP",
                      style: TextStyle(fontSize: 44, color: Colors.black),
                    ),
                    const SizedBox(height: 20),
                    // Rotated and enlarged switch section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "69",
                          style: TextStyle(fontSize: 60, color: Colors.black),
                        ),
                        const SizedBox(width: 15),
                        RotatedBox(
                          quarterTurns:
                              3, // Rotate 270 degrees to flip the switch (small toggle at bottom)
                          child: Transform.scale(
                            scale: 1.8,
                            child: Switch(
                              value:
                                  switchToggled, // Normal display - true shows small toggle, false shows large toggle
                              onChanged: (val) {
                                setState(() {
                                  switchToggled =
                                      val; // Normal input - small toggle = true, large toggle = false
                                  // Force breaker open whenever switch changes position
                                  breakerOpen = true;
                                });
                                // Send command to Arduino
                                _sendArduinoCommand();
                              },
                              activeColor: Colors.grey.shade600,
                              inactiveThumbColor: Colors.grey.shade400,
                              inactiveTrackColor: Colors.grey.shade300,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "DOWN",
                      style: TextStyle(fontSize: 44, color: Colors.black),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              // Button column - stacked vertically for better screen utilization
              Column(
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: breakerOpen ? openColor : openInactive,
                      minimumSize: const Size(250, 100),
                      side: const BorderSide(color: Colors.black, width: 3),
                    ),
                    onPressed: () => setBreakerState(true),
                    child: const Text(
                      "OPEN",
                      style: TextStyle(fontSize: 36, color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !switchToggled
                          ? closeInactive // Dark red when switch is down (safety rule prevents closing)
                          : (breakerOpen
                                ? closeInactive
                                : closeColor), // When switch is up, use breaker state
                      minimumSize: const Size(250, 100),
                      side: const BorderSide(color: Colors.black, width: 3),
                      disabledBackgroundColor: !switchToggled
                          ? closeInactive // Dark red even when disabled
                          : (breakerOpen ? closeInactive : closeColor),
                    ),
                    onPressed: switchToggled && breakerOpen
                        ? () => setBreakerState(false)
                        : null, // Only works when switch is up (true) AND breaker is open
                    child: const Text(
                      "CLOSE",
                      style: TextStyle(fontSize: 36, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
