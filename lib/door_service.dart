import 'dart:async';
import 'dart:io';

import 'device.dart';
import 'zk/client.dart';
import 'zk/protocol.dart';

class ScanUpdate {
  const ScanUpdate({required this.done, required this.total, this.found});
  final int done;
  final int total;
  final Device? found;
}

enum UnlockOutcome { opened, noReply, refused, unreachable, wrongDevice }

class UnlockResult {
  const UnlockResult(this.outcome, this.message);
  final UnlockOutcome outcome;
  final String message;
  bool get opened => outcome == UnlockOutcome.opened;
}

/// Everything the screens need from the network, so tests can swap in a fake.
abstract class DoorService {
  Stream<ScanUpdate> scan();

  /// Ask one address for its serial and name. Null if nothing answers on the ZK port.
  Future<Device?> probe(String host, {int key = 0, Duration connectTimeout});
  /// [onStatus] reports progress in plain words while it works.
  Future<UnlockResult> unlock(Device device, {int seconds = 3, void Function(String status)? onStatus});
}

class ZkDoorService implements DoorService {
  ZkDoorService({this.port = 4370, this.hosts});

  final int port;

  /// Override the hosts to scan (tests). Default: every private /24 this device is on.
  final Future<List<String>> Function()? hosts;

  static const _concurrency = 64;

  /// Private IPv4 /24 prefixes ("192.168.1") of this device's own interfaces.
  static Future<List<String>> localPrefixes() async {
    final prefixes = <String>[];
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        final p = addr.address.split('.').map(int.parse).toList();
        final private = p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && p[1] >= 16 && p[1] <= 31);
        final prefix = '${p[0]}.${p[1]}.${p[2]}';
        if (private && !prefixes.contains(prefix)) prefixes.add(prefix);
      }
    }
    return prefixes.take(3).toList();
  }

  Future<List<String>> _hosts() async {
    if (hosts != null) return hosts!();
    return [
      for (final prefix in await localPrefixes())
        for (var i = 1; i < 255; i++) '$prefix.$i',
    ];
  }

  /// Port open, then a ZK handshake for serial and name. Null if nothing listens.
  /// Some door machines (the K40 Pro we tested) can take several seconds to accept a
  /// connection and dislike quick reconnects, so they get a patient connect, a
  /// pause, and spaced-out retries.
  @override
  Future<Device?> probe(String host, {int key = 0, Duration connectTimeout = const Duration(seconds: 6)}) async {
    try {
      final s = await Socket.connect(host, port, timeout: connectTimeout);
      s.destroy();
    } catch (_) {
      return null;
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: attempt == 0 ? 800 : 2000));
      final client = ZkClient(host, port: port, key: key, timeout: const Duration(seconds: 10));
      try {
        await client.open();
        final serial = await client.serial();
        String? name;
        try {
          name = await client.deviceName();
        } on DoorError {
          name = null;
        }
        return Device(ip: host, port: port, serial: serial, name: name, key: key);
      } on DoorError {
        // try again
      } finally {
        await client.close();
      }
    }
    return Device(ip: host, port: port, key: key);
  }

  @override
  Stream<ScanUpdate> scan() {
    final controller = StreamController<ScanUpdate>();
    () async {
      final all = await _hosts();
      var next = 0;
      var done = 0;
      Future<void> worker() async {
        while (next < all.length && !controller.isClosed) {
          final host = all[next++];
          final device = await probe(host, connectTimeout: const Duration(seconds: 4));
          done++;
          if (!controller.isClosed) controller.add(ScanUpdate(done: done, total: all.length, found: device));
        }
      }

      await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
      if (!controller.isClosed) await controller.close();
    }();
    return controller.stream;
  }

  @override
  Future<UnlockResult> unlock(Device device, {int seconds = 3, void Function(String status)? onStatus}) async {
    // Connecting is safe to retry (nothing opens the door yet); the unlock itself is sent once.
    const tries = 3;
    ZkClient? client;
    for (var attempt = 1; attempt <= tries; attempt++) {
      onStatus?.call(attempt == 1 ? 'Connecting to the door machine...' : 'Still connecting (try $attempt of $tries)...');
      final c = ZkClient(device.ip, port: device.port, key: device.key, timeout: const Duration(seconds: 10));
      try {
        await c.open();
        client = c;
        break;
      } on DoorError {
        await c.close();
        if (attempt < tries) await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (client == null) {
      return UnlockResult(
        UnlockOutcome.unreachable,
        'The door machine at ${device.ip} is not answering. Check that it is powered on and that you are on the same Wi-Fi, then try again.',
      );
    }
    var sent = false;
    try {
      if (device.serial != null) {
        onStatus?.call('Checking it is the right machine...');
        final actual = await client.serial();
        if (actual != device.serial) {
          return UnlockResult(UnlockOutcome.wrongDevice, 'This address is now $actual, not ${device.serial}. Not opening.');
        }
      }
      onStatus?.call('Opening the door...');
      sent = true;
      await client.unlock(seconds);
      return const UnlockResult(UnlockOutcome.opened, 'Door unlocked');
    } on DoorError catch (e) {
      final silent = e.message.startsWith('No reply');
      if (sent && silent) {
        return const UnlockResult(UnlockOutcome.noReply, 'No answer from the device. The door may still have opened.');
      }
      if (silent) {
        return const UnlockResult(UnlockOutcome.refused, 'The door machine stopped answering before the unlock was sent. Nothing was opened. Try again.');
      }
      return UnlockResult(UnlockOutcome.refused, e.message);
    } finally {
      await client.close();
    }
  }
}
