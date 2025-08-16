import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Listen for status updates (excluding lock state)
    _bluetoothService.listenForStatusUpdates((
      breakerOpen,
      switchUp,
      lockState,
    ) {
      setState(() {
        this.breakerOpen = breakerOpen;
        switchToggled = switchUp;
        // Do NOT update locked here; lock state is only updated from lockChar notifications
      });
    });
    // Listen for lockChar notifications (two-way sync)
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
      print("Error disconnecting: $e");
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
                  bool connected = await _bluetoothService.connectToDevice(
                    device,
                  );
                  setState(() {
                    _isBluetoothConnected = connected;
                    _connectionStatus = connected
                        ? 'Connected'
                        : 'Disconnected';
                  });
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
        // Always write lock state to Arduino for two-way sync
        await _bluetoothService.writeLockState(newLockState);
        // Optionally, send breaker command if needed for your protocol
        //_sendArduinoCommand();
      },
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: locked ? Colors.orange.shade700 : Colors.blue.shade700,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 4),
        ),
        child: Center(
          child: Icon(
            locked ? Icons.lock : Icons.lock_open,
            color: Colors.white,
            size: 38,
          ),
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
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                _connectionStatus,
                style: const TextStyle(fontSize: 16, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isBluetoothConnected) ...[
                ElevatedButton(
                  onPressed: _showBluetoothDialog,
                  child: const Text(
                    'Connect to BS14',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ] else ...[
                ElevatedButton(
                  onPressed: _showBluetoothDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade100,
                  ),
                  child: const Text(
                    'Reconnect',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _disconnectFromArduino,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade100,
                  ),
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(fontSize: 14, color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchContainer({bool isPortrait = false}) {
    final double width = isPortrait ? 170 : 220;
    final double height = isPortrait ? 240 : 320;
    final double labelFont = isPortrait ? 28 : 38;
    final double numberFont = isPortrait ? 40 : 54;
    final double switchScale = isPortrait ? 1.1 : 1.3;
    final double spacing = isPortrait ? 12 : 18;
    bool forceSwitchUp = locked && !breakerOpen;
    // Disable switch if locked (regardless of breaker state)
    final bool disableSwitch = locked;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.yellow,
        border: Border.all(width: 4, color: Colors.black),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "UP",
            style: TextStyle(fontSize: labelFont, color: Colors.black),
          ),
          SizedBox(height: spacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "69",
                style: TextStyle(fontSize: numberFont, color: Colors.black),
              ),
              SizedBox(width: spacing),
              RotatedBox(
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
                                  // If locked, only update switchToggled visually, do not affect breakerOpen or send command
                                });
                              },
                        activeColor: Colors.blue,
                        activeTrackColor: Colors.blue[300],
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.grey[300],
                      ),
                      if (forceSwitchUp || disableSwitch)
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: Transform.rotate(
                            angle: 1.5708, // 90 degrees in radians
                            child: Icon(
                              Icons.lock,
                              color: Colors.orange,
                              size: 32,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing),
          Text(
            "DOWN",
            style: TextStyle(fontSize: labelFont, color: Colors.black),
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
        Stack(
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
              onPressed: () => setBreakerState(true),
              child: const Text(
                "OPEN",
                style: TextStyle(fontSize: 32, color: Colors.black),
              ),
            ),
            if (locked && !breakerOpen)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.18),
                  child: Center(
                    child: Icon(Icons.lock, color: Colors.orange, size: 38),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Opacity(
          opacity: !switchToggled ? 0.5 : 1.0,
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
                onPressed: (switchToggled && breakerOpen)
                    ? () => setBreakerState(false)
                    : null,
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
              if (locked && breakerOpen)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.18),
                    child: Center(
                      child: Icon(Icons.lock, color: Colors.orange, size: 38),
                    ),
                  ),
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
        const SizedBox(height: 24),
        Center(child: _buildSwitchContainer(isPortrait: true)),
        const SizedBox(height: 20),
        Center(child: _buildLockButton()),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  _connectionStatus,
                  style: const TextStyle(fontSize: 13, color: Colors.black),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: _showBluetoothDialog,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: const Text('Connect', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 161,
                height: 221,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.yellow,
                  border: Border.all(width: 4, color: Colors.black),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "UP",
                      style: TextStyle(fontSize: 32, color: Colors.black),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "69",
                          style: TextStyle(fontSize: 48, color: Colors.black),
                        ),
                        const SizedBox(width: 14),
                        RotatedBox(
                          quarterTurns: 3,
                          child: Transform.scale(
                            scale: 1.2,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Switch(
                                  value: switchToggled,
                                  onChanged: (val) {
                                    setState(() {
                                      switchToggled = val;
                                      breakerOpen = true;
                                    });
                                    _sendArduinoCommand();
                                  },
                                  activeColor: Colors.blue,
                                  activeTrackColor: Colors.blue[300],
                                  inactiveThumbColor: Colors.grey,
                                  inactiveTrackColor: Colors.grey[300],
                                ),
                                if (locked && !breakerOpen)
                                  Container(
                                    width: 48,
                                    height: 48,
                                    alignment: Alignment.center,
                                    child: Transform.rotate(
                                      angle: 1.5708, // 90 degrees in radians
                                      child: Icon(
                                        Icons.lock,
                                        color: Colors.orange,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "DOWN",
                      style: TextStyle(fontSize: 32, color: Colors.black),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    height: 60,
                    child: Stack(
                      children: [
                        SizedBox(
                          width: 160,
                          height: 60,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: breakerOpen
                                  ? openColor
                                  : openInactive,
                              side: const BorderSide(
                                color: Colors.black,
                                width: 3,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => setBreakerState(true),
                            child: const Text(
                              "OPEN",
                              style: TextStyle(
                                fontSize: 24,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                        if (locked && !breakerOpen)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.18),
                              child: Center(
                                child: Icon(
                                  Icons.lock,
                                  color: Colors.orange,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 160,
                    height: 60,
                    child: Stack(
                      children: [
                        SizedBox(
                          width: 160,
                          height: 60,
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
                                  borderRadius: BorderRadius.zero,
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
                                  fontSize: 24,
                                  color: Colors.black,
                                ),
                              ),
                            ),
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
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        if (locked && breakerOpen)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.18),
                              child: Center(
                                child: Icon(
                                  Icons.lock,
                                  color: Colors.orange,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              _buildLockButton(),
            ],
          ),
        ],
      ),
    );
  }
}
