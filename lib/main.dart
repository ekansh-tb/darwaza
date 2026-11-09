import 'package:flutter/material.dart';

import 'device.dart';
import 'door_service.dart';
import 'screens/door_screen.dart';
import 'screens/scan_screen.dart';
import 'store.dart';

void main() => runApp(DarwazaApp(service: ZkDoorService(), store: Store()));

class DarwazaApp extends StatefulWidget {
  const DarwazaApp({super.key, required this.service, required this.store});

  final DoorService service;
  final Store store;

  @override
  State<DarwazaApp> createState() => _DarwazaAppState();
}

class _DarwazaAppState extends State<DarwazaApp> {
  SavedState? _saved;
  bool _choosing = false;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((s) {
      if (mounted) setState(() => _saved = s);
    });
  }

  void _pick(Device device) {
    final seconds = _saved?.seconds ?? 3;
    widget.store.save(device: device, seconds: seconds);
    setState(() {
      _saved = SavedState(device: device, seconds: seconds);
      _choosing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final Widget home;
    if (saved == null) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (saved.device == null || _choosing) {
      home = ScanScreen(key: const ValueKey('scan'), service: widget.service, onPick: _pick);
    } else {
      home = DoorScreen(
        key: ValueKey('door-${saved.device!.ip}'),
        device: saved.device!,
        seconds: saved.seconds,
        service: widget.service,
        onChangeDevice: () => setState(() => _choosing = true),
        onSettings: (device, seconds) {
          widget.store.save(device: device, seconds: seconds);
          setState(() => _saved = SavedState(device: device, seconds: seconds));
        },
      );
    }
    return MaterialApp(
      title: 'Darwaza',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: home),
    );
  }
}
