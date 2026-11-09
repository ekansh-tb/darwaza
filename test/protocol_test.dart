import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:darwaza/zk/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

String hex(Uint8List b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
Uint8List unhex(String s) =>
    Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

void main() {
  final vectors = jsonDecode(File('test/fixtures/vectors.json').readAsStringSync()) as Map<String, dynamic>;

  group('golden vectors shared with door.py', () {
    for (final f in vectors['frames'] as List) {
      test('frame ${f['name']}', () {
        final got = buildPacket(f['command'] as int, f['session'] as int, f['reply_id'] as int, unhex(f['payload_hex'] as String));
        expect(hex(got), f['frame_hex']);
      });
    }
    for (final c in vectors['commkeys'] as List) {
      test('commkey key=${c['key']} session=${c['session']}', () {
        expect(hex(makeCommKey(c['key'] as int, c['session'] as int)), c['hex']);
      });
    }
  });
}
