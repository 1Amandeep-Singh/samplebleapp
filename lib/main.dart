import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:table_card_manager/core/utils/test_images.dart';

import 'features/ble/ble_repository.dart';
import 'features/ble/bloc/ble_bloc.dart';
import 'features/ble/bloc/ble_event.dart';
import 'features/ble/bloc/ble_state.dart';
import 'core/utils/epaper_image_loader.dart';
import 'core/utils/epaper_image_encoder.dart';
import 'core/utils/epaper_file_builder.dart';

void main() {
  runApp(const MyApp());
}

/// Root widget: provides BleRepository and BleBloc.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (_) => BleRepository(),
      child: BlocProvider(
        create: (context) =>
            BleBloc(repository: context.read<BleRepository>()),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'BLE Scanner',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          ),
          home: const MyHomePage(title: 'BLE Scanner'),
        ),
      ),
    );
  }
}

/// Main screen: scan, list devices, connect, show characteristics.
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _scanning = false;
  late final StreamSubscription<BleStatus> _statusSub;
  bool _bluetoothDialogVisible = false;

  String? _selectedDeviceId;
  String? _connectedDeviceName;
  DeviceConnectionState? _connectionState;
  List<Characteristic> _discoveredCharacteristics = [];

  @override
  void initState() {
    super.initState();
    // Listen to adapter status to show Bluetooth-off dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo =
          RepositoryProvider.of<BleRepository>(context, listen: false);
      final localContext = context;
      _statusSub = repo.statusStream.listen((status) {
        if (!mounted) return;
        if (status != BleStatus.ready && !_bluetoothDialogVisible) {
          _bluetoothDialogVisible = true;
          showDialog<void>(
            context: localContext,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: const Text('Bluetooth is off'),
              content: const Text('Please enable Bluetooth on your device.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(localContext).pop();
                    _bluetoothDialogVisible = false;
                  },
                  child: const Text('OK'),
                )
              ],
            ),
          );
        } else if (status == BleStatus.ready && _bluetoothDialogVisible) {
          try {
            if (Navigator.of(localContext).canPop()) {
              Navigator.of(localContext).pop();
            }
          } catch (_) {}
          _bluetoothDialogVisible = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _statusSub.cancel();
    super.dispose();
  }

  // Permissions for Android/iOS.
  Future<bool> _ensurePermissions() async {
    try {
      if (Platform.isAndroid) {
        final scan = await Permission.bluetoothScan.request();
        final connect = await Permission.bluetoothConnect.request();
        final location = await Permission.locationWhenInUse.request();
        developer.log(
          'Permission results: scan:${scan.isGranted}, '
          'connect:${connect.isGranted}, loc:${location.isGranted}',
        );
        return scan.isGranted && connect.isGranted && location.isGranted;
      } else if (Platform.isIOS) {
        final b = await Permission.bluetooth.request();
        developer.log('iOS bluetooth permission granted: ${b.isGranted}');
        return b.isGranted;
      }
      return true;
    } catch (e, st) {
      developer.log('Permission check failed', error: e, stackTrace: st);
      return false;
    }
  }

  // Start/stop scan, but keep list on stop.
  Future<void> _onStartPressed() async {
    final localContext = context;
    try {
      final ok = await _ensurePermissions();
      if (!mounted) return;
      if (!ok) {
        showDialog<void>(
          context: localContext,
          builder: (_) => AlertDialog(
            title: const Text('Bluetooth issue'),
            content: const Text(
              'Bluetooth permissions denied or adapter is off.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(localContext).pop(),
                child: const Text('OK'),
              )
            ],
          ),
        );
        return;
      }

      if (!_scanning) {
        developer.log('Starting BLE scan (filtered)');
        final serviceUuid =
            Uuid.parse('6b12ff00-4413-49c1-a307-74997b8b5941');
        context.read<BleBloc>().add(StartScan(serviceUuid: serviceUuid));
        setState(() => _scanning = true);
      } else {
        developer.log('Stopping BLE scan');
        context.read<BleBloc>().add(StopScan());
        setState(() => _scanning = false);
        // NOTE: we do not clear devices; Bloc keeps last list.
      }
    } catch (e, st) {
      developer.log('Error handling Start/Stop scan', error: e, stackTrace: st);
    }
  }

  // Build tile for a discovered device.
  Widget _buildDeviceTile(DiscoveredDevice d) {
    final name = d.name.isNotEmpty ? d.name : '<unknown>';
    final selected = d.id == _selectedDeviceId;

    return ListTile(
      selected: selected,
      selectedTileColor: Colors.grey.shade300,
      selectedColor: Colors.black,
      title: Text(
        name,
        style: const TextStyle(color: Colors.black),
      ),
      subtitle: Text(
        d.id,
        style: const TextStyle(color: Colors.black54),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(d.rssi.toString()),
          if (selected && _connectionState != null)
            Text(
              _connectionState.toString().split('.').last,
              style: const TextStyle(fontSize: 10),
            ),
        ],
      ),
      onTap: () {
        setState(() {
          _selectedDeviceId = d.id;
          _connectedDeviceName =
              d.name.isNotEmpty ? d.name : '<unknown>'; // show name immediately
        });
      },
    );
  }

  Future<void> _connectSelected() async {
    final id = _selectedDeviceId;
    if (id == null) return;
    context.read<BleBloc>().add(ConnectDevice(id));
  }

  Future<void> _disconnectSelected() async {
    final id = _selectedDeviceId;
    if (id == null) return;
    context.read<BleBloc>().add(DisconnectDevice(id));
  }


  Future<void> _sendImage() async {
    try{
        final deviceId = _selectedDeviceId;
        if (deviceId == null) return;

        developer.log('=== SEND IMAGE START ===');

        // Create test image in memory
        final Uint8List pngBytes = createHelloTextImage();
        developer.log('Step 1: Created test image, PNG bytes: ${pngBytes.length}');

        // Encode to tri-color format (black plane + red plane)
        final encoded = EpaperImageEncoder.encodeTriColor(pngBytes);
        developer.log('Step 2: Encoded to tri-color, data size: ${encoded.length} bytes');

        // Build packets (header + data)
        final packets = EpaperFileBuilder.buildPackets(encoded);
        developer.log('Step 3: Built packets, total: ${packets.length} packets');
        developer.log('  Header packet: ${packets[0].length} bytes');
        developer.log('  First data packet: ${packets[1].length} bytes');
        developer.log('  Last data packet: ${packets[packets.length-1].length} bytes');

        // Log header packet details
        final header = packets[0];
        developer.log('  Header breakdown:');
        developer.log('    [0] Operation: ${header[0]}');
        developer.log('    [1] Flooding: ${header[1]}');
        final packetCount = ByteData.sublistView(header, 2, 6).getUint32(0, Endian.big);
        developer.log('    [2-5] Packet count: $packetCount');
        final fileLength = ByteData.sublistView(header, 6, 10).getUint32(0, Endian.big);
        developer.log('    [6-9] File length: $fileLength');
        developer.log('    [10] Encryption: ${header[10]}');
        developer.log('    [11] Compression: ${header[11]}');

        final epaperCharUuid =
            Uuid.parse('7b12ff03-4413-49c1-a307-74997b8b5941');

        developer.log('Step 4: Sending ${packets.length} packets to device...');
        for (int i = 0; i < packets.length; i++) {
          context.read<BleBloc>().add(
            SendRawImage(
              deviceId: deviceId,
              characteristicUuid: epaperCharUuid,
              data: packets[i],
            ),
          );
          if (i % 50 == 0) {
            developer.log('  Sent packet $i/${packets.length}');
          }
        }
        developer.log('Step 4: All packets queued in BLoC');

        // Wait for completion polling
        final repo = context.read<BleRepository>();
        developer.log('Step 5: Polling for completion...');
        final code = await repo.notifyFileDoneAndPoll(deviceId);
        developer.log('Step 5: File done result code: $code');
        
        if (code == 1) {
          developer.log('✅ SUCCESS: Image sent and processed');
        } else if (code == 0) {
          developer.log('❌ FAILURE: Device reported failure');
        } else if (code == 10) {
          developer.log('❌ ERROR: Image data too large for device');
        } else if (code == -1) {
          developer.log('❌ TIMEOUT: Device did not respond');
        } else {
          developer.log('⚠️ UNKNOWN: Device returned code $code');
        }
        
        developer.log('=== SEND IMAGE END ===');
    }catch(e, st){
      developer.log('❌ Error in _sendImage', error: e, stackTrace: st);
    } 
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: BlocListener<BleBloc, BleState>(
        listener: (context, state) {
          if (state is BleDeviceConnectionState) {
            developer.log(
              'UI got connection state: ${state.deviceId} -> ${state.connectionState}',
            );

                    setState(() {
              if (state.connectionState == DeviceConnectionState.disconnected) {
                // After disconnect: keep list as-is, just clear connection UI
                _connectionState = null;
                _discoveredCharacteristics = [];
                _connectedDeviceName = null;
                // Optionally keep _selectedDeviceId so the row stays highlighted,
                // or set it to null if you want to deselect:
                // _selectedDeviceId = null;
              } else {
                // Connected / connecting, update connection UI
                _selectedDeviceId = state.deviceId;
                _connectionState = state.connectionState;
                _discoveredCharacteristics = state.characteristics;

                if (_connectedDeviceName == null ||
                    _connectedDeviceName == '<unknown>') {
                  final blocState = context.read<BleBloc>().state;
                  if (blocState is BleScanInProgress ||
                      blocState is BleScanStopped) {
                    final devices = blocState is BleScanInProgress
                        ? blocState.devices
                        : (blocState as BleScanStopped).devices;
                    final devs =
                        devices.where((d) => d.id == state.deviceId).toList();
                    _connectedDeviceName =
                        devs.isNotEmpty && devs.first.name.isNotEmpty
                            ? devs.first.name
                            : '<unknown>';
                  }
                }
              }
            }); 
          }
        },
        child: Column(
          children: [
            // Scan / Stop button
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: ElevatedButton(
                onPressed: _onStartPressed,
                child: Text(_scanning ? 'Stop Scan' : 'Start Scan'),
              ),
            ),

            // Connect/Disconnect/Send Test for selected device
            if (_selectedDeviceId != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _connectSelected,
                        child: const Text('Connect'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _disconnectSelected,
                        child: const Text('Disconnect'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _sendImage,
                      child: const Text('Send Image'),
                    ),
                  ],
                ),
              ),

              // Connected device name + characteristics
              if (_discoveredCharacteristics.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_connectedDeviceName != null)
                        Text(
                          _connectedDeviceName!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      const SizedBox(height: 4),
                      const Text(
                        'Discovered Characteristics:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _discoveredCharacteristics
                              .map(
                                (char) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: Chip(
                                    label: Text(
                                      (char.id.toString())
                                          .toUpperCase()
                                          .substring(0, 8),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            // Devices list: keep last known devices even after StopScan
            Expanded(
              child: BlocBuilder<BleBloc, BleState>(
                builder: (context, state) {
                  List<DiscoveredDevice> devices = [];
                  if (state is BleScanInProgress) devices = state.devices;
                  if (state is BleScanStopped) devices = state.devices;

                  return ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) =>
                        _buildDeviceTile(devices[idx]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
