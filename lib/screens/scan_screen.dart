import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../device.dart';
import '../door_service.dart';

/// Looks for door machines on the Wi-Fi by itself. If exactly one answers, it is picked for you.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.service, required this.onPick});

  final DoorService service;
  final ValueChanged<Device> onPick;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  final List<Device> _found = [];
  StreamSubscription<ScanUpdate>? _sub;
  double _progress = 0;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _sub?.cancel();
    setState(() {
      _found.clear();
      _progress = 0;
      _scanning = true;
    });
    _sub = widget.service.scan().listen(
      (u) {
        if (!mounted) return;
        setState(() {
          _progress = u.total == 0 ? 1 : u.done / u.total;
          if (u.found != null) _found.add(u.found!);
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _scanning = false);
        final named = _found.where((d) => d.serial != null).toList();
        if (named.length == 1 && _found.length == 1) widget.onPick(named.single);
      },
      onError: (_) {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _manual() async {
    final controller = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device address'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '192.168.1.100'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Use')),
        ],
      ),
    );
    if (ip == null || !RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip)) return;
    // Read its serial and name so the unlock can check it is talking to the same machine.
    final device = await widget.service.probe(ip);
    if (mounted) widget.onPick(device ?? Device(ip: ip));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 24),
              SizedBox.square(
                dimension: 200,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    painter: _RadarPainter(_scanning ? _pulse.value : 0.4, scheme.primary),
                    child: Center(child: Icon(Icons.sensor_door_outlined, size: 56, color: scheme.primary)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _scanning ? 'Looking for your door' : (_found.isEmpty ? 'No door machine found' : 'Pick your door'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _scanning ? 'Scanning this Wi-Fi network' : 'Make sure this phone is on the same Wi-Fi as the machine',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (_scanning) LinearProgressIndicator(value: _progress, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [for (final d in _found) _DeviceCard(device: d, onTap: () => widget.onPick(d))],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _scanning ? null : _start,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan again'),
                  ),
                  TextButton.icon(
                    onPressed: _manual,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Enter address'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});

  final Device device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final known = device.serial != null;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.sensor_door_outlined),
        title: Text(known ? device.title : 'Unnamed device'),
        subtitle: Text(known ? '${device.serial}  |  ${device.ip}' : '${device.ip}  |  port ${device.port} open, no answer yet'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - phase) * 0.5);
      canvas.drawCircle(center, math.max(24, maxR * phase), paint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t || old.color != color;
}
