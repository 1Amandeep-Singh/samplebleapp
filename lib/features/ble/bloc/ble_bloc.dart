import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble_repository.dart';
import 'ble_state.dart';
import 'ble_event.dart';

/// BLoC responsible for BLE scanning, connecting, writing, and notifications.
///
/// Design:
/// - All interaction with flutter_reactive_ble is via BleRepository.
/// - Streams from repository (scan, connect, notifications) never call emit
///   directly; they add events to the Bloc instead.
/// - All asynchronous logic (awaits + emits) lives inside event handlers only.
class BleBloc extends Bloc<BleEvent, BleState> {
  final BleRepository repository;

  // Scan subscription
  StreamSubscription<DiscoveredDevice>? _scanSub;

  // Connection subscription (to repository.connect stream)
  StreamSubscription<ConnectionStateUpdate>? _connSub;

  // Notifications subscription
  StreamSubscription<List<int>>? _notificationSub;

  // List of discovered devices
  final List<DiscoveredDevice> _devices = [];

  BleBloc({required this.repository}) : super(BleInitial()) {
    // Scanning events
    on<StartScan>(_onStartScan);
    on<StopScan>(_onStopScan);
    on<DeviceDiscovered>(_onDeviceDiscovered);

    // Connection events
    on<ConnectDevice>(_onConnectDevice);
    on<DisconnectDevice>(_onDisconnectDevice);
    on<InternalConnectionUpdated>(_onInternalConnectionUpdated);

    // Write command events
    on<SendCommand>(_onSendCommand);

    // Notification received events
    on<NotificationReceived>(_onNotificationReceived);

    on<SendRawImage>(_onSendRawImage);

  }

  // ---------------------------------------------------------------------------
  // SCANNING
  // ---------------------------------------------------------------------------

  /// Start scan: cancel previous scan, clear list, then pipe repository
  /// scan stream into DeviceDiscovered events.
  Future<void> _onStartScan(
    StartScan event,
    Emitter<BleState> emit,
  ) async {
    // Cancel any previous scan
    await _scanSub?.cancel();
    _scanSub = null;

    _devices.clear();
    emit(BleScanInProgress(List.unmodifiable(_devices)));

    try {
      final List<Uuid>? withServices =
          event.serviceUuid != null ? [event.serviceUuid!] : null;

      _scanSub = repository
          .scanForDevices(withServices: withServices)
          .listen((device) {
        // Route raw scan data into Bloc as events
        add(DeviceDiscovered(device));
      }, onError: (e, st) {
        developer.log('Scan stream error', error: e, stackTrace: st);
        add(StopScan());
      });
    } catch (e, st) {
      developer.log('Failed to start scan', error: e, stackTrace: st);
      emit(BleScanStopped(List.unmodifiable(_devices)));
    }
  }

  /// Stop scan and emit final list.
  Future<void> _onStopScan(
    StopScan event,
    Emitter<BleState> emit,
  ) async {
    try {
      await _scanSub?.cancel();
    } catch (e, st) {
      developer.log('Failed to stop scan', error: e, stackTrace: st);
    }
    _scanSub = null;
    emit(BleScanStopped(List.unmodifiable(_devices)));
  }

  /// Update internal devices list and emit scan state.
  void _onDeviceDiscovered(
    DeviceDiscovered event,
    Emitter<BleState> emit,
  ) {
    final device = event.device;
    final index = _devices.indexWhere((d) => d.id == device.id);
    if (index == -1) {
      _devices.add(device);
    } else {
      _devices[index] = device;
    }
    emit(BleScanInProgress(List.unmodifiable(_devices)));
  }

  // ---------------------------------------------------------------------------
  // CONNECTION
  // ---------------------------------------------------------------------------

  /// ConnectDevice:
  /// - Cancels previous connection subscription.
  /// - Subscribes to repository.connect(deviceId).
  /// - Stream listener NEVER calls emit; it dispatches _InternalConnectionUpdated.
  Future<void> _onConnectDevice(
    ConnectDevice event,
    Emitter<BleState> emit,
  ) async {
    await _connSub?.cancel();

    _connSub = repository.connect(event.deviceId).listen(
      (update) {
        add(InternalConnectionUpdated(event.deviceId, update));
      },
      onError: (e, st) {
        developer.log('Connection stream error', error: e, stackTrace: st);
      },
    );
  }

  /// Internal connection updates handler:
  /// - Emits BleDeviceConnectionState for each update.
  /// - When connected, it awaits MTU + discoverCharacteristics and then emits
  ///   an updated BleDeviceConnectionState with characteristics.
  Future<void> _onInternalConnectionUpdated(
    InternalConnectionUpdated event,
    Emitter<BleState> emit,
  ) async {
    final deviceId = event.deviceId;
    final update = event.update;

    // First emit raw connection state
    emit(BleDeviceConnectionState(
      deviceId: deviceId,
      connectionState: update.connectionState,
    ));

    if (update.connectionState == DeviceConnectionState.connected) {
      try {
        await repository.requestMtu(deviceId, 247);
      } catch (e, st) {
        developer.log('MTU request failed', error: e, stackTrace: st);
        // Not fatal, continue
      }

      List<Characteristic> characteristics = const [];
      try {
        characteristics = await repository.discoverCharacteristics(deviceId);
      } catch (e, st) {
        developer.log(
          'Failed to discover characteristics after connect',
          error: e,
          stackTrace: st,
        );
      }

      // Handler might have been closed while awaiting; guard emit.
      if (emit.isDone) return;

      emit(BleDeviceConnectionState(
        deviceId: deviceId,
        connectionState: DeviceConnectionState.connected,
        characteristics: characteristics,
      ));
    }
  }

  /// Disconnect:
  /// - Calls repository.disconnect(deviceId) to cancel underlying BLE stream.
  /// - Cancels local connection + notification subscriptions.
  /// - Emits disconnected state.
  Future<void> _onDisconnectDevice(
    DisconnectDevice event,
    Emitter<BleState> emit,
  ) async {
    try {
      await repository.disconnect(event.deviceId);
    } catch (e, st) {
      developer.log('Repository disconnect failed', error: e, stackTrace: st);
    }

    try {
      await _connSub?.cancel();
      _connSub = null;
      await _notificationSub?.cancel();
      _notificationSub = null;
    } catch (e, st) {
      developer.log(
        'Failed to cleanup connection/notifications',
        error: e,
        stackTrace: st,
      );
    }

    emit(BleDeviceConnectionState(
      deviceId: event.deviceId,
      connectionState: DeviceConnectionState.disconnected,
    ));
  }

  // ---------------------------------------------------------------------------
  // WRITE COMMAND
  // ---------------------------------------------------------------------------

  /// SendCommand:
  /// - Writes command via repository.
  /// - Emits BleCommandSent or BleCommandFailure.
  /// - Starts notifications subscription on given characteristic if not started.
  Future<void> _onSendCommand(
    SendCommand event,
    Emitter<BleState> emit,
  ) async {
    try {
      await repository.writeCommand(
        deviceId: event.deviceId,
        charUuid: event.characteristicUuid,
        data: event.data,
      );

      emit(BleCommandSent(event.data));

      // Subscribe to notifications if not already
      _notificationSub ??= repository
          .subscribeNotifications(event.deviceId, event.characteristicUuid)
          .listen((data) {
        add(NotificationReceived(
          deviceId: event.deviceId,
          characteristicUuid: event.characteristicUuid,
          data: data,
        ));
      });
    } catch (e, st) {
      developer.log('Command write failed', error: e, stackTrace: st);
      emit(BleCommandFailure(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATIONS
  // ---------------------------------------------------------------------------

  /// NotificationReceived:
  /// - For now just emits BleNotificationReceived with raw bytes.
  /// - You can extend this to parse protocol-specific messages.
  void _onNotificationReceived(
    NotificationReceived event,
    Emitter<BleState> emit,
  ) {
    emit(BleNotificationReceived(event.data));
  }

  // ---------------------------------------------------------------------------
  // CLEANUP
  // ---------------------------------------------------------------------------

  @override
  Future<void> close() async {
    try {
      await _scanSub?.cancel();
      await _connSub?.cancel();
      await _notificationSub?.cancel();
    } catch (e, st) {
      developer.log('Error during BLoC cleanup', error: e, stackTrace: st);
    }
    return super.close();
  }

  Future<void> _onSendRawImage(
  SendRawImage event,
  Emitter<BleState> emit,
) async {
  try {
    await repository.sendChunkedData(
      deviceId: event.deviceId,
      charUuid: event.characteristicUuid,
      data: event.data,
    );
    emit(BleCommandSent(event.data));
  } catch (e, st) {
    developer.log('SendRawImage failed', error: e, stackTrace: st);
    emit(BleCommandFailure(e.toString()));
  }
}

}
