import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal() {
    print("🚀 BluetoothService initialized - Debug output is working!");
  }

  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _writeCharacteristic;
  fbp.BluetoothCharacteristic? _statusCharacteristic;
  bool get isConnected =>
      _connectedDevice != null && _connectedDevice!.isConnected;

  // UUIDs matching Arduino sketch
  static const String serviceUUID = "12345678-1234-1234-1234-123456789abc";
  static const String commandCharUUID = "87654321-4321-4321-4321-cba987654321";
  static const String statusCharUUID = "11111111-2222-3333-4444-555555555555";

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

          // Subscribe to notifications for status updates (with timeout)
          if (characteristic.properties.notify) {
            try {
              print("🔔 Setting up status notifications...");
              await characteristic
                  .setNotifyValue(true)
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () {
                      print(
                        "⚠️ Status notification setup timed out, continuing anyway...",
                      );
                      return false;
                    },
                  );
              print("✅ Subscribed to status notifications");
            } catch (e) {
              print("⚠️ Could not setup status notifications: $e");
              // Continue anyway, we can still send commands
            }
          } else {
            print("⚠️ Status characteristic doesn't support notifications");
          }
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

      // Set up status listener if callbacks are already registered
      if (_statusCallbacks.isNotEmpty) {
        print(
          "🎧 Setting up status listener now that connection is established...",
        );
        await _setupStatusListener();
      }

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
  Future<void> sendBreakerCommand(bool open, bool switchUp) async {
    if (_connectedDevice == null || _writeCharacteristic == null) {
      debugPrint('No Bluetooth connection or characteristic');
      return;
    }

    // Send command matching Arduino protocol: [breakerState, switchState]
    // breakerState: 1 = Open, 0 = Close
    // switchState: 1 = Up, 0 = Down
    List<int> command = [open ? 1 : 0, switchUp ? 1 : 0];

    try {
      await _writeCharacteristic!.write(command);
      debugPrint(
        'Sent command: Breaker=${open ? "OPEN" : "CLOSE"}, Switch=${switchUp ? "UP" : "DOWN"}',
      );
    } catch (e) {
      debugPrint('Error sending command: $e');
    }
  }

  // Store multiple callback functions for status updates
  final List<Function(bool breakerOpen, bool switchUp)> _statusCallbacks = [];

  // Listen for status updates from Arduino
  Future<void> listenForStatusUpdates(
    Function(bool breakerOpen, bool switchUp) onStatusReceived,
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
    }
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
      // Enable notifications on the status characteristic
      await _statusCharacteristic!.setNotifyValue(true);
      debugPrint('✅ Enabled notifications on status characteristic');

      // Listen for real-time updates from Arduino
      _statusCharacteristic!.onValueReceived.listen(
        (value) {
          if (value.length >= 2) {
            bool breakerOpen = value[0] == 1;
            bool switchUp = value[1] == 1;
            debugPrint(
              '📨 Arduino Status Update: Breaker=${breakerOpen ? "OPEN" : "CLOSED"}, Switch=${switchUp ? "UP" : "DOWN"}',
            );

            // Notify all registered callbacks
            for (var callback in _statusCallbacks) {
              try {
                callback(breakerOpen, switchUp);
              } catch (e) {
                debugPrint('❌ Error in status callback: $e');
              }
            }
          } else {
            debugPrint('⚠️ Invalid status data length: ${value.length}');
          }
        },
        onError: (error) {
          debugPrint('❌ Error receiving status updates: $error');
        },
      );

      debugPrint('🎧 Now listening for Arduino status updates...');
    } catch (e) {
      debugPrint('❌ Error setting up status notifications: $e');
    }
  } // Disconnect from device

  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
      debugPrint('Disconnected from Bluetooth device');
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    } finally {
      _connectedDevice = null;
      _writeCharacteristic = null;
      _statusCharacteristic = null;
      _statusCallbacks.clear(); // Clear all callbacks
    }
  }
}
