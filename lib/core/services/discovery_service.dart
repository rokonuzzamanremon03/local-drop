import 'package:nsd/nsd.dart';

class DiscoveryService {
  final String _serviceType = '_directtransfer._tcp';
  Registration? _registration;
  Discovery? _discovery;

  // 1. Broadcaster (Ami ekhane achi)
  Future<void> startBroadcasting(String deviceName, int port) async {
    _registration = await register(
      Service(name: deviceName, type: _serviceType, port: port),
    );
    print('Broadcasting on network as: $deviceName');
  }

  // 2. Scanner (Ashepasher device khuje ber kora)
  Future<void> startScanning({
    required void Function(Service) onDeviceFound,
  }) async {
    _discovery = await startDiscovery(_serviceType);

    // NSD package e auto IP resolve hoy, shudhu listener add korlei hoy
    _discovery!.addListener(() {
      for (final service in _discovery!.services) {
        onDeviceFound(service);
      }
    });
  }

  // Sob connection stop kora
  Future<void> stopAll() async {
    if (_registration != null) {
      await unregister(_registration!);
    }
    if (_discovery != null) {
      await stopDiscovery(_discovery!);
    }
  }
}