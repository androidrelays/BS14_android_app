import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async'; // For Timer
import 'bluetooth_service.dart';
import 'splash_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BS14',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(), // Show splash screen first
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
  bool _showConnectionAlert = false;

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

    // Start connection monitoring
    _startConnectionMonitoring();
  }

  void _startConnectionMonitoring() {
    // Check connection status every 5 seconds
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final wasConnected = _isBluetoothConnected;
      final isConnected = _bluetoothService.isConnected;

      if (wasConnected && !isConnected) {
        // Connection lost
        _showConnectionLostAlert();
      } else if (!wasConnected && isConnected) {
        // Connection restored
        _showConnectionRestoredSnackBar();
      }

      setState(() {
        _isBluetoothConnected = isConnected;
        _connectionStatus = isConnected ? 'Connected' : 'Disconnected';
      });
    });
  }

  void _showConnectionLostAlert() {
    if (!_showConnectionAlert && mounted) {
      setState(() {
        _showConnectionAlert = true;
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('Connection Lost'),
              ],
            ),
            content: const Text(
              'Connection to Arduino has been lost. The app will attempt to reconnect automatically.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _showConnectionAlert = false;
                  });
                },
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _showConnectionAlert = false;
                  });
                  _showBluetoothDialog();
                },
                child: const Text('Reconnect'),
              ),
            ],
          );
        },
      );
    }
  }

  void _showConnectionRestoredSnackBar() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Arduino reconnected successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
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
                          ? "$deviceName (Arduino Breaker)"
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

                        // If connected, send current state to Arduino and start listening for updates
                        if (connected) {
                          _sendArduinoCommand();
                          // Set up real-time status updates from Arduino
                          await _bluetoothService.listenForStatusUpdates((
                            breakerOpen,
                            switchUp,
                          ) {
                            setState(() {
                              // Update local state with Arduino status
                              this.breakerOpen = breakerOpen;
                              switchToggled = switchUp;
                            });
                          });
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

    final Color bgColor = breakerOpen
        ? Colors.green.shade700
        : Colors.red.shade700;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;

            return SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: bgColor,
                child: isLandscape
                    ? _buildLandscapeLayout()
                    : _buildPortraitLayout(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    final Color openColor = Colors.green.shade700;
    final Color openInactive = Colors.green.shade900;
    final Color closeColor = Colors.red.shade700;
    final Color closeInactive = const Color(0xFF5D1A1A);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Bluetooth connection status at the top
          _buildBluetoothStatus(),
          const SizedBox(height: 20),
          // Switch container
          _buildSwitchContainer(),
          const SizedBox(height: 30),
          // Button column - stacked vertically for better screen utilization
          _buildControlButtons(
            openColor,
            openInactive,
            closeColor,
            closeInactive,
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    final Color openColor = Colors.green.shade700;
    final Color openInactive = Colors.green.shade900;
    final Color closeColor = Colors.red.shade700;
    final Color closeInactive = const Color(0xFF5D1A1A);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Bluetooth status at top in landscape too - more compact
          Container(
            padding: const EdgeInsets.all(6),
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
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _connectionStatus,
                  style: const TextStyle(fontSize: 10, color: Colors.black),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _showBluetoothDialog,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: const Text('Connect', style: TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Main content in a row for landscape - more compact
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Switch container - smaller in landscape
              Container(
                width: 140,
                height: 200,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.yellow,
                  border: Border.all(width: 4, color: Colors.black),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "UP",
                      style: TextStyle(fontSize: 24, color: Colors.black),
                    ),
                    const SizedBox(height: 8),
                    // Rotated and enlarged switch section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "69",
                          style: TextStyle(fontSize: 36, color: Colors.black),
                        ),
                        const SizedBox(width: 8),
                        RotatedBox(
                          quarterTurns: 3,
                          child: Transform.scale(
                            scale: 1.3,
                            child: Switch(
                              value: switchToggled,
                              onChanged: (val) {
                                setState(() {
                                  switchToggled = val;
                                  breakerOpen = true;
                                });
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
                    const SizedBox(height: 8),
                    const Text(
                      "DOWN",
                      style: TextStyle(fontSize: 24, color: Colors.black),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 30),
              // Control buttons stacked vertically in landscape - equal size, positioned to the right of switch
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Open button - using SizedBox to ensure exact sizing
                  SizedBox(
                    width: 180, // Increased from 120 to 180 (50% wider)
                    height: 80,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: breakerOpen ? openColor : openInactive,
                        side: const BorderSide(color: Colors.black, width: 3),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero, // Squared edges
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => setBreakerState(true),
                      child: const Text(
                        "OPEN",
                        style: TextStyle(fontSize: 18, color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Close button with visual feedback - exact same size as open
                  SizedBox(
                    width: 180, // Increased from 120 to 180 (50% wider)
                    height: 80,
                    child: Stack(
                      children: [
                        SizedBox(
                          width: 180, // Increased from 120 to 180 (50% wider)
                          height: 80,
                          child: Opacity(
                            opacity: !switchToggled ? 0.5 : 1.0,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: !switchToggled
                                    ? closeInactive
                                    : (breakerOpen
                                          ? closeInactive
                                          : closeColor),
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 3,
                                ),
                                shape: const RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.zero, // Squared edges
                                ),
                                padding: EdgeInsets.zero,
                                disabledBackgroundColor: !switchToggled
                                    ? closeInactive
                                    : (breakerOpen
                                          ? closeInactive
                                          : closeColor),
                              ),
                              onPressed: switchToggled && breakerOpen
                                  ? () => setBreakerState(false)
                                  : null,
                              child: const Text(
                                "CLOSE",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Overlay only when switch is down
                        if (!switchToggled)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                borderRadius:
                                    BorderRadius.zero, // Squared edges
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.block,
                                  color: Colors.white.withOpacity(0.9),
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothStatus() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _isBluetoothConnected
            ? Colors.green.shade100
            : Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: _showBluetoothDialog,
                child: const Text(
                  'Connect to BS14',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchContainer() {
    return Container(
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
          const Text("UP", style: TextStyle(fontSize: 44, color: Colors.black)),
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
                quarterTurns: 3,
                child: Transform.scale(
                  scale: 1.8,
                  child: Switch(
                    value: switchToggled,
                    onChanged: (val) {
                      setState(() {
                        switchToggled = val;
                        breakerOpen = true;
                      });
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
    );
  }

  Widget _buildControlButtons(
    Color openColor,
    Color openInactive,
    Color closeColor,
    Color closeInactive,
  ) {
    return Column(
      children: [
        // Open button - squared edges to match landscape
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: breakerOpen ? openColor : openInactive,
            minimumSize: const Size(250, 100),
            side: const BorderSide(color: Colors.black, width: 3),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero, // Squared edges
            ),
          ),
          onPressed: () => setBreakerState(true),
          child: const Text(
            "OPEN",
            style: TextStyle(fontSize: 36, color: Colors.black),
          ),
        ),
        const SizedBox(height: 20),
        // Close button with visual feedback only when switch is down
        Opacity(
          opacity: !switchToggled ? 0.5 : 1.0,
          child: Stack(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: !switchToggled
                      ? closeInactive
                      : (breakerOpen ? closeInactive : closeColor),
                  minimumSize: const Size(250, 100),
                  side: const BorderSide(color: Colors.black, width: 3),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero, // Squared edges
                  ),
                  disabledBackgroundColor: !switchToggled
                      ? closeInactive
                      : (breakerOpen ? closeInactive : closeColor),
                ),
                onPressed: switchToggled && breakerOpen
                    ? () => setBreakerState(false)
                    : null,
                child: const Text(
                  "CLOSE",
                  style: TextStyle(fontSize: 36, color: Colors.black),
                ),
              ),
              // Overlay only when switch is down
              if (!switchToggled)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius:
                          BorderRadius.zero, // Squared edges for overlay too
                    ),
                    child: Center(
                      child: Icon(
                        Icons.block,
                        color: Colors.white.withOpacity(0.9),
                        size: 48,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
