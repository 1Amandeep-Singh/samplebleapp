import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Base class for BLE events handled by [BleBloc].
abstract class BleEvent {}

/// Event to start scanning for BLE devices.
class StartScan extends BleEvent {
  final Uuid? serviceUuid;

  StartScan({this.serviceUuid});
}

/// Event to stop an ongoing scan.
class StopScan extends BleEvent {}

/// Fired internally when repository reports a newly discovered device.
class DeviceDiscovered extends BleEvent {
  final DiscoveredDevice device;

  DeviceDiscovered(this.device);
}

/// Event to send a custom command to a characteristic.
class SendCommand extends BleEvent {
  final String deviceId;
  final Uuid characteristicUuid;
  final List<int> data;

  SendCommand({
    required this.deviceId,
    required this.characteristicUuid,
    required this.data,
  });
}

/// Event emitted when a notification is received from a characteristic.
class NotificationReceived extends BleEvent {
  final String deviceId;
  final Uuid characteristicUuid;
  final List<int> data;

  NotificationReceived({
    required this.deviceId,
    required this.characteristicUuid,
    required this.data,
  });
}

/// Event to connect to a BLE device.
class ConnectDevice extends BleEvent {
  final String deviceId;

  ConnectDevice(this.deviceId);
}

/// Event to disconnect from a BLE device.
class DisconnectDevice extends BleEvent {
  final String deviceId;

  DisconnectDevice(this.deviceId);
}

/// Internal event: used by BleBloc to react to connection stream updates
/// without calling emit from inside stream listeners.
class InternalConnectionUpdated extends BleEvent {
  final String deviceId;
  final ConnectionStateUpdate update;

  InternalConnectionUpdated(this.deviceId, this.update);
}

class SendRawImage extends BleEvent {
  final String deviceId;
  final Uuid characteristicUuid;
  final Uint8List data;

  SendRawImage({
    required this.deviceId,
    required this.characteristicUuid,
    required this.data,
  });
}

