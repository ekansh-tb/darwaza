# Darwaza

One-tap door opener for ZKTeco and eSSL door machines, over your local network.

Open the app, it finds the machine on your Wi-Fi, and one big button unlocks the door.
Nothing to configure, no account, no cloud: the app talks straight to the machine.

Built with Flutter, so one codebase covers Android, iPhone and Mac.

## How it works

1. **Scan.** The app sweeps the private /24 networks it is on for devices that listen on
   TCP port 4370 (the ZK protocol port), then asks each one for its serial number and name.
   If exactly one machine answers, it is picked for you. Otherwise you choose from a list,
   or type an address.
2. **Remember.** The chosen machine (address, serial, optional comm key) and the open time
   are saved on the device, so the next launch goes straight to the unlock screen.
3. **Unlock.** One tap connects, checks that the machine at that address still reports the
   same serial number, and sends one unlock command. The ring counts down while the door
   is open.

See [docs/protocol.md](docs/protocol.md) for the wire format.

### There is no lock button

The ZK protocol only offers a timed unlock pulse: the relay opens for N seconds and the
door locks itself again. There is no "lock now" command, and the machine tested here did not
answer a door-state query either. So the app shows a countdown, never a lock button, and
never claims to know whether the door is open.

### Safety behaviour

- The unlock command is sent **once and never retried**. Connecting is retried (these
  machines can be slow to accept a connection), but nothing that opens the door is.
- If the machine answers with a different serial than the one saved, the app refuses to
  open and says so. This protects against an address being reused by another device.
- If the machine goes quiet after the unlock was sent, the app says "the door may still
  have opened" instead of reporting a failure.
- Open time is limited to 1 to 60 seconds.

## Status

| Platform | State |
|----------|-------|
| Android  | Built and run on an emulator and tested against a real machine. |
| macOS    | Project is scaffolded and has the network entitlement. Built by the CI workflow, not yet verified on a Mac by the author. |
| iPhone   | Project is scaffolded (including the Local Network usage text). Built unsigned by the CI workflow, not yet verified on a device. |

## Limits you should know about

- **Same network only.** The machine lives on your LAN, so the phone or Mac must be on the
  same Wi-Fi (or reach it over a VPN). Remote unlock from the internet is not supported.
- **Anyone on the network can send the same command** to a machine that has no comm key
  (the default, key 0). Set a communication key on the machine and enter it in the app
  settings if that matters in your building.
- The comm key is stored in the app's plain preferences for now, not in the system keychain.
- Some machines are slow or flaky about new connections. The app is patient (long
  timeouts, retries with pauses), so a scan or an unlock can take several seconds.
- Use it only on machines you own or are authorised to control. It opens a physical door.

## Build and run

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.47 or newer).
For Android you also need a JDK 17 and the Android SDK.

```
flutter pub get
flutter analyze
flutter test
flutter run            # on an attached device or emulator
flutter build apk --release
```

The tests never touch a real machine: they run against a fake ZK device on loopback.

## Installing without an app store

See [docs/install.md](docs/install.md): sideloading the Android APK, running the Mac app
built by CI, and putting the app on an iPhone with a free Apple ID.

## Building the Mac and iPhone apps

Flutter needs Xcode to build for Apple platforms. If you do not have it, use the GitHub
Actions workflow in `.github/workflows/build.yml`. It only runs when you start it
(Actions tab, Build, Run workflow), builds the macOS app by default, and can optionally
build an unsigned iPhone IPA. Android, tests and analysis are not part of CI: run them
locally.

## Project layout

```
lib/
  main.dart            app shell: loads saved state, shows scan or door screen
  device.dart          the Device model
  door_service.dart    scan, probe and unlock (the only code that touches the network)
  store.dart           saved device and open time
  zk/protocol.dart     frame builder, checksum, comm key
  zk/client.dart       one ZK session over TCP
  screens/             scan and door screens
test/
  fixtures/vectors.json   golden frames every implementation must reproduce
  fake_device.dart        a fake ZK machine on loopback
  protocol_test.dart, service_test.dart, widget_test.dart
```

## License

MIT, see [LICENSE](LICENSE).
