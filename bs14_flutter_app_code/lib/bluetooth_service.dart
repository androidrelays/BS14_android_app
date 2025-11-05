import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'dart:async';

class BluetoothService {
  // Send sense selection command to Arduino
  Future<void> sendSenseCommand(List<int> packet) async {
    if (_senseCharacteristic != null && _connectedDevice != null) {
      try {
        await _senseCharacteristic!.write(packet);
        debugPrint('Sent sense selection packet: $packet');
      } catch (e) {
        debugPrint('Error sending sense selection: $e');
      }
    } else {
      debugPrint('Sense characteristic not found or not connected');
    }
  }

  Future<void> writeLockState(bool locked) async {
    if (_lockCharacteristic != null && _connectedDevice != null) {
      try {
        await _lockCharacteristic!.write([locked ? 1 : 0]);
        debugPrint(
          'Wrote lock state to lockChar: ${locked ? 'LOCKED' : 'UNLOCKED'}',
        );

        // Android fallback: Try to read status after writing
        Future.delayed(const Duration(milliseconds: 100), () async {
          await _tryReadStatusDirectly();
        });
      } catch (e) {
        debugPrint('Error writing lock state: $e');
      }
    }
  }

  // Stream controller for lock state notifications
  final StreamController<bool> _lockStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get lockStateStream => _lockStateController.stream;
  final StreamController<int> _senseController =
      StreamController<int>.broadcast();
  Stream<int> get senseStream => _senseController.stream;
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal() {
    // Initialization without constant polling
  }

  Timer? _statusPollTimer;

  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _writeCharacteristic;
  fbp.BluetoothCharacteristic? _statusCharacteristic;
  fbp.BluetoothCharacteristic? _lockCharacteristic;
  fbp.BluetoothCharacteristic? _senseCharacteristic;
  bool get isConnected =>
      _connectedDevice != null && _connectedDevice!.isConnected;

  // UUIDs matching Arduino sketch
  static const String serviceUUID = "12345678-1234-1234-1234-123456789abc";
  static const String commandCharUUID = "87654321-4321-4321-4321-cba987654321";
  static const String statusCharUUID = "11011111-2222-3333-4444-555555555555";
  static const String lockCharUUID = "22222222-3333-4444-5555-666666666666";
  static const String senseCharUUID = "33333333-4444-5555-6666-777777777777";

  // Known Arduino MAC address for development (can be removed for production)
  static const String developmentArduinoMac = "A8:61:0A:39:64:00";

  // Device identification methods
  static bool isArduinoDevice(
    fbp.BluetoothDevice device,
    List<fbp.Guid> advertisedServices,
  ) {
    String deviceName = device.platformName.isEmpty ? '' : device.platformName;
    String deviceId = device.remoteId.toString();

    // Method 1: Check by device name pattern
    bool nameMatch =
        deviceName.contains("GIGA") ||
        deviceName.contains("Breaker") ||
        deviceName == "GIGA_Breaker_69" ||
        deviceName.startsWith("GIGA_Breaker") ||
        deviceName == "BS14" ||
        deviceName.startsWith("BS14");

    // Method 2: Check if device advertises our custom service UUID
    bool serviceMatch = advertisedServices.any(
      (serviceUuid) =>
          serviceUuid.toString().toLowerCase() == serviceUUID.toLowerCase(),
    );

    // Method 3: Development MAC address check (optional)
    bool devMacMatch =
        deviceId.toUpperCase() == developmentArduinoMac.toUpperCase();

    return nameMatch || serviceMatch || devMacMatch;
  }

  // Scan for available Bluetooth devices
  Future<List<fbp.BluetoothDevice>> scanDevices() async {
    print("🔍 Starting scanDevices() function...");
    List<fbp.BluetoothDevice> devices = [];

    try {
      // Check if Bluetooth is enabled
      if (await fbp.FlutterBluePlus.isSupported == false) {
        print("❌ Bluetooth not supported by this device");
        return devices;
      }

      // Check adapter state
      var adapterState = await fbp.FlutterBluePlus.adapterState.first;
      if (adapterState != fbp.BluetoothAdapterState.on) {
        print("⚠️ Bluetooth is not turned on, attempting to turn on");
        await fbp.FlutterBluePlus.turnOn();
        // Wait a bit for Bluetooth to turn on
        await Future.delayed(const Duration(seconds: 3));
      }

      print("📡 Starting aggressive Bluetooth scan...");

      // Listen for scan results - show ALL devices for debugging
      var subscription = fbp.FlutterBluePlus.onScanResults.listen((results) {
        print("📱 Scan results batch received with ${results.length} devices");
        for (fbp.ScanResult r in results) {
          // Show ALL devices for debugging with more detail
          String deviceName = r.device.platformName.isEmpty
              ? 'Unknown Device'
              : r.device.platformName;
          String deviceId = r.device.remoteId.toString();
          int rssi = r.rssi;

          print("Found device: $deviceName (ID: $deviceId, RSSI: $rssi)");

          // Check if this is an Arduino device using our flexible identification
          bool isArduino = isArduinoDevice(
            r.device,
            r.advertisementData.serviceUuids,
          );
          if (isArduino) {
            print(
              "🎯🎯🎯 FOUND ARDUINO DEVICE: $deviceName ($deviceId) 🎯🎯🎯",
            );
          }

          // Check if this device advertises our service UUID
          for (var serviceUuid in r.advertisementData.serviceUuids) {
            print("  - Advertised service: ${serviceUuid.toString()}");
            if (serviceUuid.toString().toLowerCase() ==
                serviceUUID.toLowerCase()) {
              print("*** FOUND DEVICE WITH OUR SERVICE UUID! ***");
            }
          }

          // Add all discovered devices to the list for debugging
          if (!devices.contains(r.device)) {
            devices.add(r.device);
            print("Added device to list: $deviceName");
          }
        }
      });

      // Start multiple scans with different parameters - reduced timeouts for faster scanning
      print("📡 Starting scan attempt 1 - scanning for service UUIDs...");
      await fbp.FlutterBluePlus.startScan(
        withServices: [
          fbp.Guid(serviceUUID),
        ], // Look specifically for our service
        timeout: const Duration(seconds: 8), // Reduced from 15 to 8 seconds
        androidUsesFineLocation: true,
      );
      await Future.delayed(const Duration(seconds: 8));
      await fbp.FlutterBluePlus.stopScan();

      print(
        "✅ Scan attempt 1 complete. Found ${devices.length} devices so far.",
      );

      // If we found any Arduino already, no need for second scan
      bool foundArduino = devices.any(
        (device) => isArduinoDevice(device, []),
      ); // Empty services list since we're checking stored devices

      if (foundArduino) {
        print("✅ Found Arduino device, skipping second scan");
      } else {
        // Second scan - general scan to catch everything, but shorter
        print("📡 Starting scan attempt 2 - general scan...");
        await fbp.FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 7), // Reduced from 15 to 7 seconds
          androidUsesFineLocation: false,
        );
        await Future.delayed(const Duration(seconds: 7));
        await fbp.FlutterBluePlus.stopScan();
      }

      // Cancel subscription
      await subscription.cancel();

      print("🏁 All scans completed. Found ${devices.length} total devices");

      // Print summary of all found devices
      print("=== DEVICE SUMMARY ===");
      for (int i = 0; i < devices.length; i++) {
        String name = devices[i].platformName.isEmpty
            ? 'Unknown Device'
            : devices[i].platformName;
        print("Device $i: $name (${devices[i].remoteId})");
      }
      print("====================");
    } catch (e) {
      print("❌ Error during scan: $e");
      print("Stack trace: ${StackTrace.current}");
    }

    return devices;
  }

  // Get bonded (paired) devices
  Future<List<fbp.BluetoothDevice>> getPairedDevices() async {
    print("📋 Getting paired devices...");
    try {
      // Check if Bluetooth is enabled first
      if (await fbp.FlutterBluePlus.isSupported == false) {
        print("❌ Bluetooth not supported by this device");
        return [];
      }

      // Check adapter state
      var adapterState = await fbp.FlutterBluePlus.adapterState.first;
      if (adapterState != fbp.BluetoothAdapterState.on) {
        print("⚠️ Bluetooth is not turned on");
        return [];
      }

      // Get connected devices first
      List<fbp.BluetoothDevice> connectedDevices =
          fbp.FlutterBluePlus.connectedDevices;
      print("📱 Found ${connectedDevices.length} connected devices");

      // Always do a fresh scan to find our Arduino
      print("🔄 Starting fresh scan for devices...");
      return await scanDevices();
    } catch (e) {
      print("❌ Error getting paired devices: $e");
      return [];
    }
  }

  // Connect to Arduino Giga
  Future<bool> connectToDevice(fbp.BluetoothDevice device) async {
    try {
      print(
        "🔄 Attempting to connect to ${device.platformName} (${device.remoteId})...",
      );

      // Check if device is already connected
      if (device.isConnected) {
        print("⚠️ Device is already connected, using existing connection");
        _connectedDevice = device;
      } else {
        print("📡 Starting BLE connection...");
        // Add connection timeout and parameters for faster connection
        await device
            .connect(
              timeout: const Duration(
                seconds: 15,
              ), // Increased timeout for initial connection
              autoConnect: false, // Faster direct connection
            )
            .timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                print("❌ Connection attempt timed out after 20 seconds");
                throw Exception("Connection timeout");
              },
            );
        _connectedDevice = device;
        print("✅ BLE connection established!");
      }

      print("🔍 Starting service discovery...");

      // Add timeout for service discovery
      List<fbp.BluetoothService> services = await device
          .discoverServices()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print("❌ Service discovery timed out after 10 seconds!");
              throw Exception("Service discovery timeout");
            },
          );

      print(
        "✅ Service discovery complete! Found ${services.length} services, looking for our service...",
      );

      // Find our specific service
      fbp.BluetoothService? breakerService;
      for (fbp.BluetoothService btService in services) {
        String serviceUuidStr = btService.uuid.toString().toLowerCase();
        print("  📋 Found service: $serviceUuidStr");
        if (serviceUuidStr == serviceUUID.toLowerCase()) {
          breakerService = btService;
          print("✅ Found our breaker service!");
          break;
        }
      }

      if (breakerService == null) {
        print("❌ Breaker service not found! Available services:");
        for (fbp.BluetoothService btService in services) {
          print("  - ${btService.uuid}");
        }
        print("💡 Expected service UUID: $serviceUUID");
        print("🔧 Check if Arduino is running the correct firmware");
        await device.disconnect();
        _connectedDevice = null;
        return false;
      }

      print("🔍 Looking for characteristics in breaker service...");

      // Find characteristics with timeout - add delay to ensure characteristics are ready
      await Future.delayed(const Duration(milliseconds: 500));

      bool foundCommand = false;

      print("📝 Available characteristics in service:");
      for (fbp.BluetoothCharacteristic characteristic
          in breakerService.characteristics) {
        String charUuidStr = characteristic.uuid.toString().toLowerCase();
        print("  📋 Characteristic: $charUuidStr");
        print(
          "    Properties: Read=${characteristic.properties.read}, Write=${characteristic.properties.write}, Notify=${characteristic.properties.notify}",
        );

        if (charUuidStr == commandCharUUID.toLowerCase()) {
          _writeCharacteristic = characteristic;
          foundCommand = true;
          print(
            "✅ Found command characteristic with write=${characteristic.properties.write}!",
          );
        } else if (charUuidStr == statusCharUUID.toLowerCase()) {
          _statusCharacteristic = characteristic;
          print(
            "✅ Found status characteristic with notify=${characteristic.properties.notify}!",
          );
          // Notifications disabled to prevent spam - using direct reads instead
          print("✅ Status characteristic ready (notifications disabled)");
        } else if (charUuidStr == lockCharUUID.toLowerCase()) {
          _lockCharacteristic = characteristic;
          print(
            "✅ Found lock characteristic with notify=${characteristic.properties.notify}, write=${characteristic.properties.write}",
          );
          // Notifications disabled to prevent spam - using direct reads instead
          print("✅ Found lock characteristic (notifications disabled)");
        } else if (charUuidStr == senseCharUUID.toLowerCase()) {
          _senseCharacteristic = characteristic;
          print(
            "✅ Found sense characteristic with write=${characteristic.properties.write}!",
          );
        }
      }

      if (!foundCommand) {
        print("❌ Command characteristic not found!");
        print("💡 Expected command UUID: $commandCharUUID");
        print(
          "🔧 Check Arduino firmware - ensure BLE.addCharacteristic() for command characteristic",
        );
        await device.disconnect();
        _connectedDevice = null;
        return false;
      }

      print("🎉 Bluetooth connection fully established!");
      print("📡 Connection summary:");
      print("  ✅ Device: ${device.platformName} (${device.remoteId})");
      print("  ✅ Service: Found");
      print(
        "  ✅ Command characteristic: ${_writeCharacteristic != null ? 'Ready' : 'Missing'}",
      );
      print(
        "  ✅ Status characteristic: ${_statusCharacteristic != null ? 'Ready' : 'Missing'}",
      );
      print(
        "  ✅ Lock characteristic: ${_lockCharacteristic != null ? 'Ready' : 'Missing'}",
      );

      // Set up status listener if callbacks are already registered
      if (_statusCallbacks.isNotEmpty) {
        print(
          "🎧 Setting up status listener now that connection is established...",
        );
        await _setupStatusListener();

        // Perform initial sync since we have callbacks
        await _performInitialSync();
      } else {
        print(
          "⏳ No status callbacks registered yet - initial sync will happen when callbacks are registered",
        );
      }
      // Enable sense notifications
      listenForSenseUpdates();

      return true;
    } catch (e) {
      print('❌ Error connecting to device: $e');
      print('📍 Error type: ${e.runtimeType}');

      // Clean up on error
      try {
        print("🧹 Cleaning up connection...");
        await device.disconnect();
      } catch (disconnectError) {
        print('⚠️ Error during cleanup disconnect: $disconnectError');
      }

      _connectedDevice = null;
      _writeCharacteristic = null;
      _statusCharacteristic = null;
      return false;
    }
  }

  // Send breaker command to Arduino
  Future<void> sendBreakerCommand(bool open, bool switchUp, bool locked) async {
    if (_connectedDevice == null || _writeCharacteristic == null) {
      debugPrint('No Bluetooth connection or characteristic');
      return;
    }

    // Send command matching Arduino protocol: [breakerState, switchState, lockState]
    // breakerState: 1 = Open, 0 = Close
    // switchState: 1 = Up, 0 = Down
    // lockState: 1 = Locked, 0 = Unlocked
    List<int> command = [open ? 1 : 0, switchUp ? 1 : 0, locked ? 1 : 0];

    try {
      await _writeCharacteristic!.write(command);
      debugPrint(
        'Sent command: Breaker=${open ? "OPEN" : "CLOSE"}, Switch=${switchUp ? "UP" : "DOWN"}, Lock=${locked ? "LOCKED" : "UNLOCKED"}',
      );

      // Android fallback: If notifications might not be working,
      // try to read the status characteristic after a short delay
      Future.delayed(const Duration(milliseconds: 100), () async {
        await _tryReadStatusDirectly();
      });
    } catch (e) {
      debugPrint('Error sending command: $e');
    }
  }

  // Perform initial sync sequence - extracted from connection establishment
  Future<void> _performInitialSync() async {
    print("🔄 Starting initial sync sequence...");

    // First read after shorter delay - Arduino waits 800ms before writing
    await Future.delayed(const Duration(milliseconds: 200));
    await _tryReadStatusDirectly();

    // Second read to catch Arduino's update (Arduino writes after 800ms)
    await Future.delayed(const Duration(milliseconds: 700));
    await _tryReadStatusDirectly();

    // Third read to ensure we get the most current state
    await Future.delayed(const Duration(milliseconds: 500));
    await _tryReadStatusDirectly();
    await _tryReadStatusDirectly();

    print("🔄 Initial sync sequence completed");

    // Also read the lock characteristic directly with multiple attempts
    for (int attempt = 1; attempt <= 3; attempt++) {
      if (_lockCharacteristic != null && _lockCharacteristic!.properties.read) {
        try {
          print(
            "🔍 Reading lock characteristic directly (attempt $attempt)...",
          );
          List<int> lockValue = await _lockCharacteristic!.read();
          print("🔒 Read lock data: $lockValue (length: ${lockValue.length})");

          if (lockValue.isNotEmpty) {
            bool lockState = lockValue[0] == 1;
            print("🎯 Parsed lock state: ${lockState ? 'LOCKED' : 'UNLOCKED'}");
            _lockStateController.add(lockState);
            break; // Success, exit retry loop
          } else {
            print("⚠️ Lock data is empty (attempt $attempt)");
          }
        } catch (e) {
          print("❌ Error reading lock characteristic (attempt $attempt): $e");
          if (attempt == 3) {
            print("🔒 Using default lock state: false");
            _lockStateController.add(false);
          }
        }
      }

      // Small delay between attempts
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  // Android fallback: Try to read status directly if notifications aren't working
  Future<void> _tryReadStatusDirectly() async {
    print("🔍 Attempting to read status characteristic directly...");

    if (_statusCharacteristic == null) {
      print("❌ Status characteristic is null - cannot read");
      return;
    }

    try {
      if (_statusCharacteristic!.properties.read) {
        print("📖 Reading status characteristic...");
        List<int> value = await _statusCharacteristic!.read();
        print("📊 Read status data: $value (length: ${value.length})");

        if (value.length >= 2) {
          bool breakerOpen = value[0] == 1;
          bool switchUp = value[1] == 1;
          bool? locked;
          if (value.length >= 3) {
            locked = value[2] == 1;
          }

          print(
            "🎯 Parsed status: breaker=${breakerOpen ? 'OPEN' : 'CLOSED'}, switch=${switchUp ? 'UP' : 'DOWN'}, locked=${locked ?? 'unknown'}",
          );

          // Notify all registered callbacks
          for (var callback in _statusCallbacks) {
            try {
              callback(breakerOpen, switchUp, locked);
            } catch (e) {
              print('❌ Error in direct read callback: $e');
            }
          }
        } else {
          print(
            "⚠️ Status data too short (${value.length} bytes), expected at least 2",
          );
        }
      } else {
        print("❌ Status characteristic does not support read operations");
      }
    } catch (e) {
      print("❌ Error reading status characteristic: $e");
    }
  }

  // Force a status sync - useful for manual connection issues
  Future<void> forceStatusSync() async {
    print('🔄 Forcing status synchronization...');

    // Try to read status characteristic
    await _tryReadStatusDirectly();

    // Also try to read lock characteristic
    if (_lockCharacteristic != null && _lockCharacteristic!.properties.read) {
      try {
        print("🔍 Force reading lock characteristic...");
        List<int> lockValue = await _lockCharacteristic!.read();
        print(
          "🔒 Force read lock data: $lockValue (length: ${lockValue.length})",
        );

        if (lockValue.isNotEmpty) {
          bool lockState = lockValue[0] == 1;
          print(
            "🎯 Force parsed lock state: ${lockState ? 'LOCKED' : 'UNLOCKED'}",
          );
          _lockStateController.add(lockState);
        } else {
          print("⚠️ Force read lock data is empty");
        }
      } catch (e) {
        print("❌ Error force reading lock characteristic: $e");
      }
    } else {
      print(
        "❌ Lock characteristic is null or does not support read operations in force sync",
      );
    }

    print('🔄 Force status sync completed');
  }

  // Store multiple callback functions for status updates
  final List<Function(bool breakerOpen, bool switchUp, bool? locked)>
  _statusCallbacks = [];

  // Listen for status updates from Arduino
  Future<void> listenForStatusUpdates(
    Function(bool breakerOpen, bool switchUp, bool? locked) onStatusReceived,
  ) async {
    // Add callback to the list (avoid duplicates)
    if (!_statusCallbacks.contains(onStatusReceived)) {
      _statusCallbacks.add(onStatusReceived);
      debugPrint(
        '✅ Status update callback registered (total: ${_statusCallbacks.length})',
      );
    }

    // If we're already connected, set up the listener immediately
    if (_statusCharacteristic != null && _statusCallbacks.length == 1) {
      await _setupStatusListener();

      // CRITICAL FIX: Trigger initial sync now that we have callbacks registered
      print("🔄 Triggering initial sync now that callbacks are registered...");
      await Future.delayed(
        const Duration(milliseconds: 100),
      ); // Small delay to ensure setup complete
      await _performInitialSync();
    }
  }

  // Clear all status callbacks - useful for reconnections
  void clearStatusCallbacks() {
    _statusCallbacks.clear();
    debugPrint('🗑️ All status callbacks cleared');
  }

  // Remove a status update callback
  void removeStatusListener(
    Function(bool breakerOpen, bool switchUp) onStatusReceived,
  ) {
    _statusCallbacks.remove(onStatusReceived);
    debugPrint(
      '🗑️ Status update callback removed (remaining: ${_statusCallbacks.length})',
    );
  }

  // Internal method to set up the actual listener
  Future<void> _setupStatusListener() async {
    if (_statusCharacteristic == null) {
      debugPrint('❌ No status characteristic available');
      return;
    }

    try {
      debugPrint('🔔 Setting up status listener with Android compatibility...');

      // Android-specific: Ensure notifications are properly enabled
      await _statusCharacteristic!.setNotifyValue(true);

      // Android workaround: Small delay to ensure descriptor is written
      await Future.delayed(const Duration(milliseconds: 200));

      // Verify notification is actually enabled
      bool isNotifying = _statusCharacteristic!.isNotifying;
      debugPrint('📡 Status characteristic notification state: $isNotifying');

      if (!isNotifying) {
        debugPrint('⚠️ Retrying status notification setup...');
        await _statusCharacteristic!.setNotifyValue(false);
        await Future.delayed(const Duration(milliseconds: 100));
        await _statusCharacteristic!.setNotifyValue(true);
        await Future.delayed(const Duration(milliseconds: 200));
        isNotifying = _statusCharacteristic!.isNotifying;
        debugPrint(
          '📡 Status characteristic notification state after retry: $isNotifying',
        );
      }

      // Listen for real-time updates from Arduino
      _statusCharacteristic!.onValueReceived.listen(
        (value) {
          if (value.length >= 2) {
            bool breakerOpen = value[0] == 1;
            bool switchUp = value[1] == 1;
            bool? locked;
            if (value.length >= 3) {
              locked = value[2] == 1;
            }

            // Notify all registered callbacks
            for (var callback in _statusCallbacks) {
              try {
                callback(breakerOpen, switchUp, locked);
              } catch (e) {
                debugPrint('❌ Error in status callback: $e');
              }
            }
          }
        },
        onError: (error) {
          debugPrint('❌ Error receiving status updates: $error');
        },
      );

      debugPrint('🎧 Status listener configured and active');
    } catch (e) {
      debugPrint('❌ Error setting up status notifications: $e');
    }
  }

  // Listen for sense selection updates from Arduino
  void listenForSenseUpdates() {
    if (_senseCharacteristic != null &&
        _senseCharacteristic!.properties.notify) {
      _senseCharacteristic!.setNotifyValue(true);
      _senseCharacteristic!.value.listen((value) {
        if (value.isNotEmpty) {
          _senseController.add(value[0]);
        }
      });
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    try {
      _statusPollTimer?.cancel();
      _statusPollTimer = null;
      await _connectedDevice?.disconnect();
      debugPrint('Disconnected from Bluetooth device');
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    } finally {
      _connectedDevice = null;
      _writeCharacteristic = null;
      _statusCharacteristic = null;
      _lockCharacteristic = null;
      _senseCharacteristic = null;
      _statusCallbacks.clear(); // Clear all callbacks
    }
  }
}
