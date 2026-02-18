import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:table_card_manager/core/utils/constants.dart';

import 'dart:typed_data'; //for Uint8List
/// Repository for BLE operations: scanning, writing commands, subscribing
/// notifications, connecting/disconnecting devices, and building custom packets.
class BleRepository {
  /// Reactive BLE instance
  final FlutterReactiveBle _ble;

  /// Map to track active connection subscriptions by deviceId
  final Map<String, StreamSubscription<ConnectionStateUpdate>> _connections = {};

  /// Constructor, allows injecting a BLE instance (useful for testing)
  BleRepository({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  /// Request a specific MTU for a connected device
  Future<int> requestMtu(String deviceId, int mtu) async {
    try {
      return await _ble.requestMtu(deviceId: deviceId, mtu: mtu);
    } catch (e, st) {
      developer.log('requestMtu failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// ----------------- SCANNING -----------------

  /// Start scanning for devices, optionally filtering by service UUID.
  Stream<DiscoveredDevice> scanForDevices({List<Uuid>? withServices}) {
    try {
      return _ble.scanForDevices(
        // if null, do unfiltered scan; caller can pass [BleCharacteristics.espaperUuid]
        withServices: withServices ?? const [],
        scanMode: ScanMode.lowLatency,
      );
    } catch (e, st) {
      developer.log('BleRepository.scanForDevices failed', error: e, stackTrace: st);
      return Stream<DiscoveredDevice>.error(e, st);
    }
  }

  /// BLE adapter status stream
  Stream<BleStatus> get statusStream => _ble.statusStream;

  /// ----------------- CONNECTION -----------------

  /// Connect to a BLE device and emit connection updates.
  ///
  /// Also tracks the underlying subscription so [disconnect] can cancel it.
  Stream<ConnectionStateUpdate> connect(String deviceId) {
    final connectionStream = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 5),
    );

    final broadcast = connectionStream.asBroadcastStream();

    final sub = broadcast.listen(
      (event) {
        developer.log(
          'Device $deviceId connection state: ${event.connectionState}',
        );
      },
      onError: (e, st) {
        developer.log('Connection error for $deviceId', error: e, stackTrace: st);
      },
    );

    _connections[deviceId] = sub;

    return broadcast;
  }

  /// Disconnect a connected device by cancelling its subscription
  Future<void> disconnect(String deviceId) async {
    try {
      final sub = _connections[deviceId];
      if (sub != null) {
        await sub.cancel();
        _connections.remove(deviceId);
        developer.log('Device $deviceId disconnected');
      }
    } catch (e, st) {
      developer.log('Disconnect failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// ----------------- CHARACTERISTICS -----------------

  /// Helper to create a qualified characteristic dynamically
  QualifiedCharacteristic _qualified(Uuid charId, String deviceId) =>
      QualifiedCharacteristic(
        serviceId: BleCharacteristics.connectionServiceUuid,
        characteristicId: charId,
        deviceId: deviceId,
      );

  /// Write a custom packet to a characteristic, waiting for peripheral ACK
  Future<void> writeToCharacteristicWithResponse(
    String deviceId,
    Uuid charUuid,
    List<int> data,
  ) async {
    try {
      // small delay if your device needs a gap after connect
      await Future.delayed(const Duration(milliseconds: 200));
      final qc = _qualified(charUuid, deviceId);
      developer.log('Writing to $charUuid: $data');
      await _ble.writeCharacteristicWithResponse(qc, value: data);
    } catch (e, st) {
      developer.log(
        'writeToCharacteristicWithResponse failed',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Subscribe to notifications from a specific characteristic
  Stream<List<int>> subscribeNotifications(String deviceId, Uuid charUuid) {
    final qc = _qualified(charUuid, deviceId);
    return _ble.subscribeToCharacteristic(qc);
  }

  /// Discover characteristics for the BLE device's connection service
  Future<List<Characteristic>> discoverCharacteristics(String deviceId) async {
    try {
      // Important: discover all services before reading them
      await _ble.discoverAllServices(deviceId);

      final services = await _ble.getDiscoveredServices(deviceId);
      final service = services.firstWhere(
        (s) => s.id == BleCharacteristics.connectionServiceUuid,
        orElse: () => throw Exception('Service not found'),
      );
      developer.log(
        'Discovered ${service.characteristics.length} characteristics '
        'for service ${BleCharacteristics.connectionServiceUuid}',
      );
      return service.characteristics;
    } catch (e, st) {
      developer.log('discoverCharacteristics failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Write a custom command packet to a characteristic
  Future<void> writeCommand({
    required String deviceId,
    required Uuid charUuid,
    required List<int> data,
  }) async {
    await writeToCharacteristicWithResponse(deviceId, charUuid, data);
  }



   /// Send a large buffer in BLE-sized chunks to a characteristic.
  ///
  /// [chunkSize] should usually be <= (MTU - 3). If you previously requested
  /// MTU 247, then 200 is a safe default.
  Future<void> sendChunkedData({
    required String deviceId,
    required Uuid charUuid,
    required Uint8List data,
    int chunkSize = 200,
  }) async {
    int offset = 0;
    while (offset < data.length) {
      final end = (offset + chunkSize).clamp(0, data.length);
      final chunk = data.sublist(offset, end);
      await writeToCharacteristicWithResponse(deviceId, charUuid, chunk);
      offset = end;
    }
  }


   static final Uuid _fileDoneUuid =
      Uuid.parse('7b12ff10-4413-49c1-a307-74997b8b5941');

  Future<int> notifyFileDoneAndPoll(String deviceId) async {
    final doneFlag = Uint8List.fromList([0x01]);

    // 1) Write "file done" marker to 7b12ff10 using your existing helper
    await writeToCharacteristicWithResponse(
      deviceId,
      _fileDoneUuid,
      doneFlag,
    );

    // 2) Poll result by reading the same characteristic directly via _ble
    const maxTries = 20;
    for (int i = 0; i < maxTries; i++) {
      final qc = _qualified(_fileDoneUuid, deviceId);
      final result = await _ble.readCharacteristic(qc);

      if (result.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      final code = result.first;
      if (code != 2) {
        // 1=success, 0=failure, 10=image too large
        return code;
      }

      await Future.delayed(const Duration(milliseconds: 200));
    }

    return -1; // timeout
  }
}