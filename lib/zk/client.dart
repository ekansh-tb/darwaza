import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart';

/// One ZK session over TCP: connect, read a few options, pulse the door relay.
class ZkClient {
  ZkClient(this.host, {this.port = 4370, this.key = 0, this.timeout = const Duration(seconds: 8)});

  final String host;
  final int port;
  final int key;
  final Duration timeout;

  Socket? _sock;
  final List<int> _buf = [];
  Completer<void>? _wake;
  Object? _error;
  bool _closed = false;
  int _session = 0;
  int _replyId = ushrtMax - 1;

  Future<void> open() async {
    try {
      final sock = await Socket.connect(host, port, timeout: timeout);
      _sock = sock;
      sock.listen(
        (data) {
          _buf.addAll(data);
          _notify();
        },
        onError: (Object e) {
          _error = e;
          _notify();
        },
        onDone: () {
          _closed = true;
          _notify();
        },
        cancelOnError: true,
      );
    } on SocketException catch (e) {
      throw DoorError('Cannot reach $host:$port (${e.message})');
    } on TimeoutException {
      throw DoorError('Cannot reach $host:$port (timed out)');
    }
    var reply = await _send(cmdConnect);
    _session = reply.session;
    if (reply.code == cmdAckUnauth) {
      reply = await _send(cmdAuth, makeCommKey(key, _session));
    }
    if (reply.code != cmdAckOk) {
      throw DoorError('The device refused the connection (wrong comm key?)');
    }
  }

  void _notify() {
    final w = _wake;
    _wake = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> _readExact(int n) async {
    final deadline = DateTime.now().add(timeout);
    while (_buf.length < n) {
      if (_error != null) throw DoorError('Connection error: $_error');
      if (_closed) throw DoorError('The device closed the connection');
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) throw DoorError('No reply from the device');
      final wake = Completer<void>();
      _wake = wake;
      try {
        await wake.future.timeout(left);
      } on TimeoutException {
        throw DoorError('No reply from the device');
      }
    }
    final out = Uint8List.fromList(_buf.sublist(0, n));
    _buf.removeRange(0, n);
    return out;
  }

  Future<Reply> _send(int command, [Uint8List? payload]) async {
    final sock = _sock;
    if (sock == null) throw DoorError('Not connected');
    sock.add(buildPacket(command, _session, _replyId, payload));
    _replyId = (_replyId + 1) % ushrtMax;
    final top = ByteData.sublistView(await _readExact(8));
    if (top.getUint16(0, Endian.little) != top1 || top.getUint16(2, Endian.little) != top2) {
      throw DoorError('Not a ZK device');
    }
    final length = top.getUint32(4, Endian.little);
    if (length < 8 || length > 1 << 20) throw DoorError('Not a ZK device');
    final body = await _readExact(length);
    final bd = ByteData.sublistView(body);
    _replyId = bd.getUint16(6, Endian.little);
    return Reply(
      bd.getUint16(0, Endian.little),
      bd.getUint16(4, Endian.little),
      _replyId,
      Uint8List.sublistView(body, 8),
    );
  }

  Future<String> option(String name) async {
    final payload = Uint8List.fromList([...utf8.encode('~$name'), 0]);
    final reply = await _send(cmdOptionsRrq, payload);
    if (reply.code != cmdAckOk) throw DoorError('The device did not return $name');
    final text = latin1.decode(reply.data);
    final value = text.contains('=') ? text.substring(text.lastIndexOf('=') + 1) : text;
    final end = value.indexOf('\u0000');
    return (end >= 0 ? value.substring(0, end) : value).trim();
  }

  Future<String> serial() => option('SerialNumber');
  Future<String> deviceName() => option('DeviceName');

  /// Pulse the door relay for [seconds] (the device counts in 100 ms units). Sent once, never retried.
  Future<void> unlock(int seconds) async {
    if (seconds < 1 || seconds > 60) throw DoorError('Seconds must be 1 to 60');
    final payload = ByteData(4)..setUint32(0, seconds * 10, Endian.little);
    final reply = await _send(cmdUnlock, payload.buffer.asUint8List());
    if (reply.code != cmdAckOk) throw DoorError('The device did not accept the unlock');
  }

  Future<void> close() async {
    final sock = _sock;
    if (sock == null) return;
    _sock = null;
    if (!_closed && _error == null) {
      try {
        // Tell the device we are leaving (it cleans up its session), but never wait on it.
        sock.add(buildPacket(cmdExit, _session, _replyId));
        await sock.flush().timeout(const Duration(milliseconds: 500));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } catch (_) {
        // the line may already be gone
      }
    }
    sock.destroy();
  }
}
