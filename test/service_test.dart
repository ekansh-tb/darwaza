import 'package:darwaza/device.dart';
import 'package:darwaza/door_service.dart';
import 'package:darwaza/zk/client.dart';
import 'package:darwaza/zk/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_device.dart';

void main() {
  late FakeDevice dev;
  setUp(() async => dev = await FakeDevice.start());
  tearDown(() => dev.stop());

  group('ZkClient', () {
    test('reads serial and name', () async {
      final c = ZkClient('127.0.0.1', port: dev.port);
      await c.open();
      expect(await c.serial(), 'TEST-SERIAL-0001');
      expect(await c.deviceName(), 'Test Door Machine');
      await c.close();
    });

    test('unlock sends one pulse in 100 ms units', () async {
      final c = ZkClient('127.0.0.1', port: dev.port);
      await c.open();
      await c.unlock(3);
      await c.close();
      expect(dev.unlockUnits, [30]);
    });

    test('rejects silly durations without sending', () async {
      final c = ZkClient('127.0.0.1', port: dev.port);
      await c.open();
      for (final bad in [0, -1, 61]) {
        expect(() => c.unlock(bad), throwsA(isA<DoorError>()));
      }
      await c.close();
      expect(dev.unlockUnits, isEmpty);
    });

    test('comm key device accepts the right key and refuses the wrong one', () async {
      final keyed = await FakeDevice.start(key: 4321);
      addTearDown(keyed.stop);
      final ok = ZkClient('127.0.0.1', port: keyed.port, key: 4321);
      await ok.open();
      expect(await ok.serial(), 'TEST-SERIAL-0001');
      await ok.close();
      expect(() => ZkClient('127.0.0.1', port: keyed.port, key: 1).open(), throwsA(isA<DoorError>()));
    });
  });

  group('ZkDoorService', () {
    test('unlock opens the door once and reports progress in order', () async {
      final svc = ZkDoorService(port: dev.port);
      final statuses = <String>[];
      final r = await svc.unlock(Device(ip: '127.0.0.1', port: dev.port, serial: 'TEST-SERIAL-0001'), seconds: 2, onStatus: statuses.add);
      expect(r.outcome, UnlockOutcome.opened);
      expect(dev.unlockUnits, [20]);
      expect(statuses, ['Connecting to the door machine...', 'Checking it is the right machine...', 'Opening the door...']);
    });

    test('a different serial at the address is refused and nothing is sent', () async {
      final svc = ZkDoorService(port: dev.port);
      final r = await svc.unlock(Device(ip: '127.0.0.1', port: dev.port, serial: 'SOMEONE-ELSE'));
      expect(r.outcome, UnlockOutcome.wrongDevice);
      expect(dev.unlockUnits, isEmpty);
    });

    test('a silent device after the unlock is reported as maybe-open, never retried', () async {
      dev.dropUnlockReply = true;
      final svc = ZkDoorService(port: dev.port);
      final r = await svc.unlock(Device(ip: '127.0.0.1', port: dev.port, serial: 'TEST-SERIAL-0001'));
      expect(r.outcome, UnlockOutcome.noReply);
      expect(dev.unlockUnits.length, 1);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('nothing listening means unreachable', () async {
      final port = dev.port;
      await dev.stop();
      final svc = ZkDoorService(port: port);
      final r = await svc.unlock(Device(ip: '127.0.0.1', port: port));
      expect(r.outcome, UnlockOutcome.unreachable);
      expect(r.message, contains('127.0.0.1'));
      expect(r.message, contains('not answering'));
    });

    test('scan finds the fake device and skips closed hosts', () async {
      final svc = ZkDoorService(port: dev.port, hosts: () async => ['127.0.0.1', '127.0.0.2']);
      final updates = await svc.scan().toList();
      final found = updates.map((u) => u.found).whereType<Device>().toList();
      expect(found.length, 1);
      expect(found.single.serial, 'TEST-SERIAL-0001');
      expect(found.single.name, 'Test Door Machine');
      expect(updates.last.done, 2);
    });
  });
}
