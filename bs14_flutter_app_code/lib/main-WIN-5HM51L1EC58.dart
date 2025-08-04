import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'dart:async';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BS14',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool breakerOpen = true;
  bool switchToggled = true;
  Timer? _statusTimer;
  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _characteristic;
  bool _isBluetoothConnected = false;
  String _connectionStatus = "Scanning for BS14...";

  final String serviceUuid = "12345678-1234-1234-1234-123456789abc";
  final String characteristicUuid = "87654321-4321-4321-4321-cba987654321";

  @override
  void initState() {
    super.initState();
    // Allow both orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _scanAndConnect();
  }

  Future<void> _scanAndConnect() async {
    print("🔍 Starting scan for BS14...");
    setState(() {
      _connectionStatus = "Scanning for BS14...";
    });

    // Start scanning
    await fbp.FlutterBluePlus.startScan(timeout: Duration(seconds: 10));

    // Listen for scan results
    fbp.FlutterBluePlus.scanResults.listen((results) async {
      for (fbp.ScanResult result in results) {
        print(
          "📡 Found device: ${result.device.platformName} (${result.device.remoteId})",
        );

        if (result.device.platformName == "BS14") {
          print("🎯 Found BS14! Connecting...");
          await fbp.FlutterBluePlus.stopScan();
          await _connectToDevice(result.device);
          break;
        }
      }
    });
  }

  Future<void> _connectToDevice(fbp.BluetoothDevice device) async {
    try {
      setState(() {
        _connectionStatus = "Connecting to BS14...";
      });

      await device.connect();
      _connectedDevice = device;
      print("✅ Connected to BS14!");

      setState(() {
        _isBluetoothConnected = true;
        _connectionStatus = "Connected to BS14";
      });

      // Discover services
      List<fbp.BluetoothService> services = await device.discoverServices();

      for (fbp.BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() ==
            serviceUuid.toLowerCase()) {
          print("🔍 Found breaker service!");

          for (fbp.BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                characteristicUuid.toLowerCase()) {
              _characteristic = characteristic;
              print("🔍 Found breaker characteristic!");

              // Start polling for status updates
              _startStatusPolling();
              break;
            }
          }
          break;
        }
      }
    } catch (e) {
      print("❌ Connection failed: $e");
      setState(() {
        _isBluetoothConnected = false;
        _connectionStatus = "Connection failed";
      });
    }
  }

  void _startStatusPolling() {
    print("🔄 Starting status polling every 1 second...");

    _statusTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      if (_characteristic != null && _connectedDevice != null) {
        try {
          // Read current status from Arduino
          List<int> value = await _characteristic!.read();

          if (value.length >= 2) {
            bool newBreakerOpen = value[0] == 1;
            bool newSwitchUp = value[1] == 1;

            print(
              "📖 Read Arduino status: Breaker=${newBreakerOpen ? 'OPEN' : 'CLOSED'}, Switch=${newSwitchUp ? 'UP' : 'DOWN'}",
            );

            // Update UI if state changed
            if (newBreakerOpen != breakerOpen || newSwitchUp != switchToggled) {
              setState(() {
                breakerOpen = newBreakerOpen;
                switchToggled = newSwitchUp;
              });
              print(
                "🎨 UI updated from Arduino - Breaker: ${breakerOpen ? 'OPEN' : 'CLOSED'}, Switch: ${switchToggled ? 'UP' : 'DOWN'}",
              );
            }
          }
        } catch (e) {
          print("⚠️ Failed to read status: $e");
        }
      }
    });
  }

  Future<void> _sendArduinoCommand() async {
    if (_characteristic != null && _connectedDevice != null) {
      try {
        // Send breaker and switch state to Arduino
        List<int> command = [breakerOpen ? 1 : 0, switchToggled ? 1 : 0];
        await _characteristic!.write(command);
        print(
          "📤 Sent to Arduino: Breaker=${breakerOpen ? 'OPEN' : 'CLOSED'}, Switch=${switchToggled ? 'UP' : 'DOWN'}",
        );
      } catch (e) {
        print("❌ Failed to send command: $e");
      }
    }
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

    Widget content = Center(
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
                    "Open",
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
                    "Close",
                    style: TextStyle(fontSize: 36, color: Colors.black),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Use OrientationBuilder to respond to device orientation changes
    return Scaffold(
      backgroundColor: bgColor,
      body: OrientationBuilder(
        builder: (context, orientation) {
          if (orientation == Orientation.landscape) {
            // Landscape layout - arrange horizontally
            return Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.all(15),
                  color: bgColor,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Bluetooth connection status at the top
                      Container(
                        padding: const EdgeInsets.all(10),
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
                              color: _isBluetoothConnected
                                  ? Colors.green
                                  : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _connectionStatus,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Switch container (bigger for landscape)
                          Container(
                            width: 180,
                            height: 250,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.yellow,
                              border: Border.all(width: 4, color: Colors.black),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "UP",
                                  style: TextStyle(
                                    fontSize: 30,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Rotated and enlarged switch section
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "69",
                                      style: TextStyle(
                                        fontSize: 42,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    RotatedBox(
                                      quarterTurns:
                                          3, // Rotate 270 degrees to flip the switch (small toggle at bottom)
                                      child: Transform.scale(
                                        scale: 1.4,
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
                                          inactiveThumbColor:
                                              Colors.grey.shade400,
                                          inactiveTrackColor:
                                              Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  "DOWN",
                                  style: TextStyle(
                                    fontSize: 30,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Button column for landscape
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: breakerOpen
                                      ? openColor
                                      : openInactive,
                                  minimumSize: const Size(160, 75),
                                  side: const BorderSide(
                                    color: Colors.black,
                                    width: 3,
                                  ),
                                ),
                                onPressed: () => setBreakerState(true),
                                child: const Text(
                                  "Open",
                                  style: TextStyle(
                                    fontSize: 28,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: !switchToggled
                                      ? closeInactive // Dark red when switch is down (safety rule prevents closing)
                                      : (breakerOpen
                                            ? closeInactive
                                            : closeColor), // When switch is up, use breaker state
                                  minimumSize: const Size(160, 75),
                                  side: const BorderSide(
                                    color: Colors.black,
                                    width: 3,
                                  ),
                                  disabledBackgroundColor: !switchToggled
                                      ? closeInactive // Dark red even when disabled
                                      : (breakerOpen
                                            ? closeInactive
                                            : closeColor),
                                ),
                                onPressed: switchToggled && breakerOpen
                                    ? () => setBreakerState(false)
                                    : null, // Only works when switch is up (true) AND breaker is open
                                child: const Text(
                                  "Close",
                                  style: TextStyle(
                                    fontSize: 28,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          } else {
            // Portrait layout - original vertical arrangement
            return content;
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _connectedDevice?.disconnect();
    // Reset to portrait when leaving the screen
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }
}
