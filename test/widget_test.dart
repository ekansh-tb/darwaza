import 'dart:async';

import 'package:darwaza/device.dart';
import 'package:darwaza/door_service.dart';
import 'package:darwaza/main.dart';
import 'package:darwaza/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeService implements DoorService {
  FakeService({this.devices = const [], this.result = const UnlockResult(UnlockOutcome.opened, 'Door unlocked'), this.gate});

  /// When set, unlock reports a status and then waits for this to complete.
  final Completer<void>? gate;

  final List<Device> devices;
  final UnlockResult result;
  final List<(Device, int)> unlocks = [];

  @override
  Stream<ScanUpdate> scan() async* {
    for (var i = 0; i < devices.length; i++) {
      yield ScanUpdate(done: i + 1, total: devices.length, found: devices[i]);
    }
    if (devices.isEmpty) yield const ScanUpdate(done: 1, total: 1);
  }

  @override
  Future<Device?> probe(String host, {int key = 0, Duration connectTimeout = const Duration(seconds: 1)}) async => devices.where((d) => d.ip == host).firstOrNull;

  @override
  Future<UnlockResult> unlock(Device device, {int seconds = 3, void Function(String status)? onStatus}) async {
    unlocks.add((device, seconds));
    if (gate != null) {
      onStatus?.call('Still connecting (try 2 of 3)...');
      await gate!.future;
    }
    return result;
  }
}

const door = Device(ip: '192.168.1.50', serial: 'TEST-SERIAL-0001', name: 'Test Door Machine');

/// The radar animation never stops, so scan screens cannot use pumpAndSettle.
Future<void> letScanFinish(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('one device found: picked automatically, then one tap unlocks', (tester) async {
    final service = FakeService(devices: [door]);
    await tester.pumpWidget(DarwazaApp(service: service, store: Store()));
    await letScanFinish(tester);
    await tester.pumpAndSettle();

    expect(find.text('Tap to unlock'), findsOneWidget);
    expect(find.text('Test Door Machine'), findsOneWidget);

    await tester.tap(find.byKey(const Key('unlock-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Open'), findsOneWidget);
    expect(service.unlocks.single.$1, door);
    expect(service.unlocks.single.$2, 3);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Locked again'), findsOneWidget);
  });

  testWidgets('two devices found: the user picks one', (tester) async {
    const other = Device(ip: '192.168.1.60', serial: 'AAA111', name: 'Gym door');
    await tester.pumpWidget(DarwazaApp(service: FakeService(devices: [door, other]), store: Store()));
    await letScanFinish(tester);

    expect(find.text('Pick your door'), findsOneWidget);
    await tester.tap(find.text('Gym door'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to unlock'), findsOneWidget);
    expect(find.textContaining('AAA111'), findsOneWidget);
  });

  testWidgets('nothing found shows the empty state', (tester) async {
    await tester.pumpWidget(DarwazaApp(service: FakeService(), store: Store()));
    await letScanFinish(tester);
    expect(find.text('No door machine found'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
  });

  testWidgets('a saved device skips the scan; a refusal is shown', (tester) async {
    SharedPreferences.setMockInitialValues({'device': '{"ip":"192.168.1.50","port":4370,"serial":"TEST-SERIAL-0001","name":"Test Door Machine","key":0}'});
    final service = FakeService(result: const UnlockResult(UnlockOutcome.unreachable, 'Cannot reach 192.168.1.50:4370'));
    await tester.pumpWidget(DarwazaApp(service: service, store: Store()));
    await tester.pumpAndSettle();

    expect(find.text('Tap to unlock'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unlock-button')));
    await tester.pumpAndSettle();
    expect(find.text('Cannot reach 192.168.1.50:4370'), findsOneWidget);
  });

  testWidgets('the seconds setting is remembered and sent', (tester) async {
    SharedPreferences.setMockInitialValues({'device': '{"ip":"192.168.1.50","port":4370,"serial":"TEST-SERIAL-0001","name":"Test Door Machine","key":0}'});
    final service = FakeService();
    await tester.pumpWidget(DarwazaApp(service: service, store: Store()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 s'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Opens for 5 seconds, then locks by itself.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('unlock-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.unlocks.single.$2, 5);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('progress is shown while connecting, so it never just spins', (tester) async {
    SharedPreferences.setMockInitialValues({'device': '{"ip":"192.168.1.50","port":4370,"serial":"TEST-SERIAL-0001","name":"Test Door Machine","key":0}'});
    final gate = Completer<void>();
    await tester.pumpWidget(DarwazaApp(service: FakeService(gate: gate), store: Store()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('unlock-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Still connecting (try 2 of 3)...'), findsOneWidget);

    gate.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Open'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
