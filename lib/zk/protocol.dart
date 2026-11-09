// The ZK wire format, byte for byte what door.py speaks. test/fixtures/vectors.json
// is the contract: every frame and comm key below must reproduce it exactly.

import 'dart:typed_data';

const int ushrtMax = 65535;
const int top1 = 20560; // 0x5050
const int top2 = 32130; // 0x7d82

const int cmdConnect = 1000;
const int cmdExit = 1001;
const int cmdAuth = 1102;
const int cmdOptionsRrq = 11;
const int cmdUnlock = 31;
const int cmdAckOk = 2000;
const int cmdAckUnauth = 2005;

class DoorError implements Exception {
  DoorError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The 16-bit one's complement sum the firmware expects (from zkemsdk.c).
int checksum(Uint8List data) {
  var total = 0;
  var i = 0;
  while (i + 1 < data.length) {
    total += data[i] | (data[i + 1] << 8);
    if (total > ushrtMax) total -= ushrtMax;
    i += 2;
  }
  if (i < data.length) total += data[i];
  while (total > ushrtMax) {
    total -= ushrtMax;
  }
  total = ~total;
  while (total < 0) {
    total += ushrtMax;
  }
  return total;
}

/// Scramble the communication password for CMD_AUTH (from commpro.c).
Uint8List makeCommKey(int key, int sessionId, {int ticks = 50}) {
  var k = 0;
  for (var i = 0; i < 32; i++) {
    k = (key & (1 << i)) != 0 ? ((k << 1) | 1) : (k << 1);
  }
  k = (k + sessionId) & 0xFFFFFFFF;
  // XOR with "ZKSO", swap the two 16-bit halves, mix in the ticks byte. The lowest
  // byte (^ 'Z') ends up unused by the final layout, as in the C original.
  final b1 = ((k >> 8) & 0xFF) ^ 0x4B; // 'K'
  final b2 = ((k >> 16) & 0xFF) ^ 0x53; // 'S'
  final b3 = ((k >> 24) & 0xFF) ^ 0x4F; // 'O'
  final t = ticks & 0xFF;
  return Uint8List.fromList([b2 ^ t, b3 ^ t, t, b1 ^ t]);
}

/// The full TCP frame for one command. [replyId] is the value before the +1 bump.
Uint8List buildPacket(int command, int session, int replyId, [Uint8List? payload]) {
  final data = payload ?? Uint8List(0);
  final head = ByteData(8)
    ..setUint16(0, command, Endian.little)
    ..setUint16(2, 0, Endian.little)
    ..setUint16(4, session, Endian.little)
    ..setUint16(6, replyId, Endian.little);
  final sum = checksum(Uint8List.fromList([...head.buffer.asUint8List(), ...data]));
  final bodyLen = 8 + data.length;
  final out = ByteData(8 + bodyLen)
    ..setUint16(0, top1, Endian.little)
    ..setUint16(2, top2, Endian.little)
    ..setUint32(4, bodyLen, Endian.little)
    ..setUint16(8, command, Endian.little)
    ..setUint16(10, sum, Endian.little)
    ..setUint16(12, session, Endian.little)
    ..setUint16(14, (replyId + 1) % ushrtMax, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(16, 16 + data.length, data);
  return bytes;
}

class Reply {
  Reply(this.code, this.session, this.replyId, this.data);
  final int code;
  final int session;
  final int replyId;
  final Uint8List data;
}
