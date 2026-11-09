# The ZK protocol, as Darwaza uses it

Darwaza speaks the small part of the ZKTeco ("ZK") machine protocol it needs over TCP
port 4370: connect, read two options, unlock, exit. This is an unofficial description
written from the behaviour of the machine tested and from the open-source `pyzk` library.
All numbers are little-endian.

## Frame

Every message, in both directions, is:

```
offset  size  field
0       2     0x5050  (20560)   magic part 1
2       2     0x7d82  (32130)   magic part 2
4       4     length of everything after this field
8       2     command (or reply code)
10      2     checksum
12      2     session id
14      2     reply id
16      n     payload
```

`length` is `8 + n`.

### Checksum

A 16-bit one's complement sum over the 8-byte header (with the checksum field zeroed, and
the reply id as it was before the +1 bump described below) followed by the payload:

```
total = 0
for each pair of bytes (lo, hi): total += lo | (hi << 8); if total > 65535: total -= 65535
if one byte is left: total += that byte
while total > 65535: total -= 65535
checksum = (~total) mod 65535  (kept in 16 bits)
```

See `checksum` in `lib/zk/protocol.dart`.

### Reply id

The client starts at 65534. Each command is sent with `reply id + 1` (wrapping at 65535)
in the frame while the checksum is computed with the value before the bump. The machine
echoes a reply id, which the client uses as the next starting value.

## Commands used

| Command | Code | Payload | Reply |
|---------|------|---------|-------|
| CONNECT | 1000 | none | 2000 (OK) with the session id, or 2005 (unauthorised) |
| AUTH | 1102 | scrambled comm key (4 bytes) | 2000 or 2005 |
| OPTIONS_RRQ | 11 | `~SerialNumber\0` or `~DeviceName\0` | 2000 with `Name=value\0` |
| UNLOCK | 31 | uint32: seconds * 10 | 2000 |
| EXIT | 1001 | none | 2000 |

Flow: CONNECT. If the reply is 2005, send AUTH with the comm key scrambled using the
session id from the CONNECT reply. Then read options, then UNLOCK once, then EXIT.

### Comm key scrambling

The communication key (a number, 0 for none) is mixed with the session id and the ASCII
bytes `ZKSO`. See `makeCommKey` in `lib/zk/protocol.dart`. It is obfuscation, not security.

## What is not here

- No lock command: UNLOCK is a timed pulse, the door relocks by itself.
- No door-state query: the machine tested did not answer one.
- Nothing that writes users, clears logs or changes machine settings is implemented, on
  purpose: the app only reads two options and pulses the relay.

## Golden vectors

`test/fixtures/vectors.json` holds exact frames (command, session, reply id, payload and
the resulting bytes in hex) and comm key outputs. `test/protocol_test.dart` rebuilds each
one. The checksum and comm key were also cross-checked against `pyzk` when the vectors
were made. If you port the protocol to another language, make it reproduce these bytes
first.

## Quirks of real machines

- A new connection can take several seconds to be accepted, or time out.
- Reconnecting immediately after a session can leave the machine silent for a moment, so
  the app pauses between attempts and says goodbye (EXIT) before closing.
- Replies may arrive split across TCP segments: read exactly `length` bytes.
