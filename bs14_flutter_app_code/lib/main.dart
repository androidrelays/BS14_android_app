this iimport 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'bluetooth_service.dart';
import 'settings_screen.dart';
import 'sense_command.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool locked = false;
  StreamSubscription<bool>? _lockCharSubscription;
  bool switchToggled = true;
  bool breakerOpen = true;
  final BluetoothService _bluetoothService = BluetoothService();
  bool _isBluetoothConnected = false;
  String _connectionStatus = 'Disconnected';
  bool _showConnectionAlert = false;
  String _senseMode = 'A'; // Default to Sense A

  @override
  void initState() {
    _loadSenseMode();
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Listen for status updates (including lock state for proper synchronization)
    _bluetoothService.listenForStatusUpdates((
      breakerOpen,
      switchUp,
      lockState,
    ) {
      setState(() {
        this.breakerOpen = breakerOpen;
        switchToggled = switchUp;
        if (lockState != null) {
          locked = lockState;
        }
      });
    });
    // Listen for sense selection changes from Arduino
    _bluetoothService.senseStream.listen((senseValue) async {
      String newSense = senseValue == 0 ? 'A' : 'B';
      if (newSense != _senseMode) {
        setState(() => _senseMode = newSense);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('sense_mode', newSense);
      }
    });
    _lockCharSubscription = _bluetoothService.lockStateStream.listen((
      lockState,
    ) {
      setState(() {
        locked = lockState;
      });
    });
    _startConnectionMonitoring();
  }

  void _startConnectionMonitoring() {
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final wasConnected = _isBluetoothConnected;
      final isConnected = _bluetoothService.isConnected;
      if (wasConnected && !isConnected) {
        _showConnectionLostAlert();
      } else if (!wasConnected && isConnected) {
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

  void _disconnectFromArduino() async {
    try {
      await _bluetoothService.disconnect();
      // Clear callbacks when disconnecting to prepare for fresh registration on reconnect
      _bluetoothService.clearStatusCallbacks();
      setState(() {
        _isBluetoothConnected = false;
        _connectionStatus = 'Disconnected';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.bluetooth_disabled, color: Colors.white),
                SizedBox(width: 8),
                Text('Disconnected from Arduino'),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error disconnecting: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
    _bluetoothService.disconnect();
    _lockCharSubscription?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _loadSenseMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _senseMode = prefs.getString('sense_mode') ?? 'A';
      });
    } catch (_) {}
  }

  Future<void> _saveSenseMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sense_mode', mode);
    setState(() {
      _senseMode = mode;
    });
    // Send sense selection to Arduino if connected
    if (_bluetoothService.isConnected) {
      final packet = SenseCommand.getSensePacket(mode);
      await _bluetoothService.sendSenseCommand(packet);
    }
  }

  void setBreakerState(bool open) {
    if (!locked) {
      setState(() {
        if (open) {
          breakerOpen = true;
        } else if (switchToggled) {
          breakerOpen = false;
        }
      });
      _sendArduinoCommand();
    }
  }

  void _sendArduinoCommand() async {
    if (_bluetoothService.isConnected) {
      await _bluetoothService.sendBreakerCommand(
        breakerOpen,
        switchToggled,
        locked,
      );
    }
  }

  void _showBluetoothDialog() async {
    try {
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
      if (mounted) Navigator.of(context).pop();
      if (!mounted) return;
      if (devices.isEmpty) {
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
              ],
            );
          },
        );
        return;
      }
      // Show a dialog to select a device and connect
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return SimpleDialog(
            title: const Text('Select Device'),
            children: devices.map((device) {
              return SimpleDialogOption(
                child: Text(
                  device.platformName.isEmpty
                      ? device.remoteId.toString()
                      : device.platformName,
                ),
                onPressed: () async {
                  Navigator.of(context).pop();
                  print(
                    "🔄 Clearing old callbacks and registering fresh ones...",
                  );
                  _bluetoothService.clearStatusCallbacks();
                  await _bluetoothService.listenForStatusUpdates((
                    breakerOpen,
                    switchUp,
                    lockState,
                  ) {
                    setState(() {
                      this.breakerOpen = breakerOpen;
                      switchToggled = switchUp;
                      if (lockState != null) {
                        locked = lockState;
                      }
                    });
                  });
                  print(
                    "✅ Status callbacks registered before connection attempt",
                  );
                  bool connected = await _bluetoothService.connectToDevice(
                    device,
                  );
                  setState(() {
                    _isBluetoothConnected = connected;
                    _connectionStatus = connected
                        ? 'Connected'
                        : 'Disconnected';
                  });
                  // Send sense selection to Arduino after connection
                  if (connected) {
                    final packet = SenseCommand.getSensePacket(_senseMode);
                    await _bluetoothService.sendSenseCommand(packet);
                  }
                  if (!connected && mounted) {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('Connection Failed'),
                          content: const Text(
                            'Could not connect to the selected device.',
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
                },
              );
            }).toList(),
          );
        },
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
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

  Widget _buildLockButton() {
    return GestureDetector(
      onLongPress: () async {
        final newLockState = !locked;
        setState(() {
          locked = newLockState;
        });
        await _bluetoothService.writeLockState(newLockState);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 8,
        ), // Smaller, tighter padding
        decoration: BoxDecoration(
          color: locked ? Colors.orange.shade700 : Colors.blue.shade700,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Text(
          locked ? 'HOLD TO UNLOCK' : 'HOLD TO LOCK',
          style: const TextStyle(
            fontSize: 22,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ), // Black text, smaller font
        ),
      ),
    );
  }

  Widget _buildBluetoothStatus() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(10),
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
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                _connectionStatus,
                style: const TextStyle(fontSize: 16, color: Colors.black),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SettingsScreen(
                        initialSense: _senseMode,
                        onSenseChanged: (mode) => _saveSenseMode(mode),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: _isBluetoothConnected
                    ? _disconnectFromArduino
                    : _showBluetoothDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBluetoothConnected
                      ? Colors.red.shade100
                      : Colors.blue.shade100,
                ),
                child: Text(
                  _isBluetoothConnected ? 'Disconnect' : 'Connect to BS14',
                  style: TextStyle(
                    fontSize: 14,
                    color: _isBluetoothConnected ? Colors.red : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchContainer({bool isPortrait = false}) {
    final double width = isPortrait ? 220 : 180;
    final double height = isPortrait ? 260 : 220; // taller in landscape
    final double labelFont = isPortrait
        ? 32
        : 32; // same font size for all labels
    final double numberFont = labelFont; // 69 label same size as UP/DOWN
    final double switchScale = isPortrait ? 2.0 : 1.7;
    bool forceSwitchUp = locked && !breakerOpen;
    final bool disableSwitch = locked;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.yellow,
        border: Border.all(width: 4, color: Colors.black),
      ),
      child: Stack(
        children: [
          // UP label at the top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                "UP",
                style: TextStyle(
                  fontSize: labelFont,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // DOWN label at the bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Text(
                "DOWN",
                style: TextStyle(
                  fontSize: labelFont,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (isPortrait)
            // 69 label left, switch slightly left of center
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 69 label at far left
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "69",
                    style: TextStyle(
                      fontSize: numberFont,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Expanded to push switch left of center
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Transform.scale(
                        scale: switchScale,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Switch(
                              value: forceSwitchUp ? true : switchToggled,
                              onChanged: (disableSwitch || forceSwitchUp)
                                  ? null
                                  : (val) {
                                      setState(() {
                                        switchToggled = val;
                                        if (!locked) {
                                          breakerOpen = true;
                                          _sendArduinoCommand();
                                        }
                                      });
                                    },
                              activeColor: Colors.blue,
                              activeTrackColor: Colors.blue[300],
                              inactiveThumbColor: Colors.grey,
                              inactiveTrackColor: Colors.grey[300],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (!isPortrait)
            Stack(
              children: [
                // 69 label at far left, vertically centered
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      "69",
                      style: TextStyle(
                        fontSize: numberFont,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Switch centered
                Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Transform.scale(
                      scale: switchScale,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Switch(
                            value: forceSwitchUp ? true : switchToggled,
                            onChanged: (disableSwitch || forceSwitchUp)
                                ? null
                                : (val) {
                                    setState(() {
                                      switchToggled = val;
                                      if (!locked) {
                                        breakerOpen = true;
                                        _sendArduinoCommand();
                                      }
                                    });
                                  },
                            activeColor: Colors.blue,
                            activeTrackColor: Colors.blue[300],
                            inactiveThumbColor: Colors.grey,
                            inactiveTrackColor: Colors.grey[300],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Bold UP and DOWN labels in landscape
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      "UP",
                      style: TextStyle(
                        fontSize: labelFont,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Text(
                      "DOWN",
                      style: TextStyle(
                        fontSize: labelFont,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
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
        // OPEN BUTTON
        Opacity(
          opacity: locked ? 0.5 : 1.0,
          child: Stack(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: breakerOpen ? openColor : openInactive,
                  minimumSize: const Size(220, 70),
                  side: const BorderSide(color: Colors.black, width: 3),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                onPressed: locked ? null : () => setBreakerState(true),
                child: const Text(
                  "OPEN",
                  style: TextStyle(fontSize: 32, color: Colors.black),
                ),
              ),
              if (locked)
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.18)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // CLOSE BUTTON
        Opacity(
          opacity: (locked || !switchToggled) ? 0.5 : 1.0,
          child: Stack(
            children: <Widget>[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: !switchToggled
                      ? closeInactive
                      : (breakerOpen ? closeInactive : closeColor),
                  minimumSize: const Size(220, 70),
                  side: const BorderSide(color: Colors.black, width: 3),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  disabledBackgroundColor: !switchToggled
                      ? closeInactive
                      : (breakerOpen ? closeInactive : closeColor),
                ),
                onPressed: (locked || !switchToggled || !breakerOpen)
                    ? null
                    : () => setBreakerState(false),
                child: const Text(
                  "CLOSE",
                  style: TextStyle(fontSize: 32, color: Colors.black),
                ),
              ),
              if (!switchToggled)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.block,
                        color: Colors.white.withOpacity(0.9),
                        size: 38,
                      ),
                    ),
                  ),
                ),
              if (locked)
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.18)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!switchToggled && !breakerOpen) {
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
            return Container(
              padding: const EdgeInsets.all(16),
              color: bgColor,
              child: isLandscape
                  ? _buildLandscapeLayout()
                  : _buildPortraitLayout(),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: _buildBluetoothStatus(),
        ),
        const SizedBox(height: 18),
        Center(child: _buildLockButton()),
        const SizedBox(height: 18),
        Center(child: _buildSwitchContainer(isPortrait: true)),
        const SizedBox(height: 20),
        Center(
          child: _buildControlButtons(
            openColor,
            openInactive,
            closeColor,
            closeInactive,
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout() {
    final Color openColor = Colors.green.shade700;
    final Color openInactive = Colors.green.shade900;
    final Color closeColor = Colors.red.shade700;
    final Color closeInactive = const Color(0xFF5D1A1A);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Bluetooth controls on the left
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBluetoothStatus(),
              const SizedBox(height: 12),
              _buildLockButton(),
            ],
          ),
          const SizedBox(width: 32),
          // Switch container in the middle
          Center(child: _buildSwitchContainer(isPortrait: false)),
          const SizedBox(width: 32),
          // Control buttons on the right
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButtons(
                openColor,
                openInactive,
                closeColor,
                closeInactive,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
