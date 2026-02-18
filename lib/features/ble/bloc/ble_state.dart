import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Base state for BLE scanning, connections, commands and notifications.
abstract class BleState {}

/// Initial state before any scan has started.
class BleInitial extends BleState {}

/// Emitted while a scan is in progress.
class BleScanInProgress extends BleState {
  final List<DiscoveredDevice> devices;

  BleScanInProgress(this.devices);
}

/// Emitted when a scan has stopped; contains the final list of discovered devices.
class BleScanStopped extends BleState {
  final List<DiscoveredDevice> devices;

  BleScanStopped(this.devices);
}

/// Emitted when connection state for a device changes.
class BleDeviceConnectionState extends BleState {
  final String deviceId;
  final DeviceConnectionState connectionState;

  /// Optionally expose discovered characteristics for this device.
  final List<Characteristic> characteristics;

  BleDeviceConnectionState({
    required this.deviceId,
    required this.connectionState,
    this.characteristics = const [],
  });
}

/// Emitted when a BLE command has been successfully written to a characteristic.
class BleCommandSent extends BleState {
  /// The data that was sent to the characteristic.
  final List<int> data;

  BleCommandSent(this.data);
}

/// Emitted when a BLE command write fails.
class BleCommandFailure extends BleState {
  final String error;

  BleCommandFailure(this.error);
}

/// Emitted whenever a notification is received from a subscribed characteristic.
class BleNotificationReceived extends BleState {
  /// Raw byte data received from the characteristic.
  final List<int> data;

  BleNotificationReceived(this.data);
}
