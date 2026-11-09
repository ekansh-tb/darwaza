import 'dart:io';
import 'dart:typed_data';

import 'package:darwaza/zk/protocol.dart';

/// A fake ZK door machine on loopback. The real one is never touched by tests.
class FakeDevice {
  FakeDevice._(this._server, this.serial, this.name, this.key);

  final ServerSocket _server;
  final String serial;
  final String name;
  final int? key;
  final List<int> unlockUnits = [];
  final List<int> commands = [];
  bool dropUnlockReply = false;

  int get port => _server.port;

  static Future<FakeDevice> start({String serial = 'TEST-SERIAL-0001', String name = 'Test Door Machine', int? key}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final dev = FakeDevice._(server, serial, name, key);
    server.listen(dev._serve);
    return dev;
  }

  Future<void> stop() => _server.close();

  void _serve(Socket conn) {
    final buf = <int>[];
    var authed = key == null;
    const session = 4242;
    conn.listen((data) {
      buf.addAll(data);
      while (buf.length >= 8) {
        final len = ByteData.sublistView(Uint8List.fromList(buf.sublist(0, 8))).getUint32(4, Endian.little);
        if (buf.length < 8 + len) return;
        final body = Uint8List.fromList(buf.sublist(8, 8 + len));
        buf.removeRange(0, 8 + len);
        final bd = ByteData.sublistView(body);
        final cmd = bd.getUint16(0, Endian.little);
        final sentSum = bd.getUint16(2, Endian.little);
        final rid = bd.getUint16(6, Endian.little);
        final payload = Uint8List.sublistView(body, 8);
        // the firmware checks the checksum with the reply id as it was before the bump
        final original = rid == 0 ? ushrtMax - 1 : rid - 1;
        final head = ByteData(8)
          ..setUint16(0, cmd, Endian.little)
          ..setUint16(2, 0, Endian.little)
          ..setUint16(4, bd.getUint16(4, Endian.little), Endian.little)
          ..setUint16(6, original, Endian.little);
        if (checksum(Uint8List.fromList([...head.buffer.asUint8List(), ...payload])) != sentSum) {
          conn.destroy();
          return;
        }
        commands.add(cmd);
        void reply(int code, [List<int> data = const []]) {
          final out = ByteData(16 + data.length)
            ..setUint16(0, top1, Endian.little)
            ..setUint16(2, top2, Endian.little)
            ..setUint32(4, 8 + data.length, Endian.little)
            ..setUint16(8, code, Endian.little)
            ..setUint16(12, session, Endian.little)
            ..setUint16(14, rid, Endian.little);
          final bytes = out.buffer.asUint8List();
          bytes.setRange(16, 16 + data.length, data);
          conn.add(bytes);
        }

        if (cmd == cmdConnect) {
          reply(authed ? cmdAckOk : cmdAckUnauth);
        } else if (cmd == cmdAuth) {
          final want = makeCommKey(key!, session);
          authed = payload.length == 4 && List.generate(4, (i) => payload[i] == want[i]).every((e) => e);
          reply(authed ? cmdAckOk : cmdAckUnauth);
        } else if (!authed) {
          reply(cmdAckUnauth);
        } else if (cmd == cmdOptionsRrq) {
          final which = String.fromCharCodes(payload.where((b) => b != 0));
          final value = which == '~SerialNumber' ? serial : name;
          reply(cmdAckOk, [...'${which.substring(1)}=$value'.codeUnits, 0]);
        } else if (cmd == cmdUnlock) {
          unlockUnits.add(ByteData.sublistView(payload).getUint32(0, Endian.little));
          if (!dropUnlockReply) reply(cmdAckOk);
        } else if (cmd == cmdExit) {
          reply(cmdAckOk);
          conn.destroy();
        }
      }
    }, onError: (_) {});
  }
}
