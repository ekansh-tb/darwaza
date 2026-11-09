import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../device.dart';
import '../door_service.dart';

enum _Phase { idle, opening, open, problem }

/// One big button. The ZK protocol can only pulse the relay, so the ring counts the
/// seconds until the door locks itself; there is no lock button to press.
class DoorScreen extends StatefulWidget {
  const DoorScreen({
    super.key,
    required this.device,
    required this.seconds,
    required this.service,
    required this.onChangeDevice,
    required this.onSettings,
  });

  final Device device;
  final int seconds;
  final DoorService service;
  final VoidCallback onChangeDevice;
  final void Function(Device device, int seconds) onSettings;

  @override
  State<DoorScreen> createState() => _DoorScreenState();
}

class _DoorScreenState extends State<DoorScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(vsync: this);
  _Phase _phase = _Phase.idle;
  String _message = '';

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_phase == _Phase.opening || _phase == _Phase.open) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.opening;
      _message = 'Opening...';
    });
    final result = await widget.service.unlock(
      widget.device,
      seconds: widget.seconds,
      onStatus: (status) {
        if (mounted && _phase == _Phase.opening) setState(() => _message = status);
      },
    );
    if (!mounted) return;
    if (result.opened) {
      HapticFeedback.heavyImpact();
      setState(() {
        _phase = _Phase.open;
        _message = 'Open';
      });
      _ring.duration = Duration(seconds: widget.seconds);
      await _ring.forward(from: 0);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _message = 'Locked again';
      });
    } else {
      setState(() {
        _phase = _Phase.problem;
        _message = result.message;
      });
    }
  }

  Future<void> _settings() async {
    final updated = await showModalBottomSheet<(Device, int)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SettingsSheet(device: widget.device, seconds: widget.seconds),
    );
    if (updated != null) widget.onSettings(updated.$1, updated.$2);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final open = _phase == _Phase.open;
    final problem = _phase == _Phase.problem;
    final ringColor = problem ? scheme.error : (open ? scheme.tertiary : scheme.primary);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Text(widget.device.title, style: text.titleLarge),
                        Text(
                          [widget.device.serial, widget.device.ip].whereType<String>().join('  |  '),
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Find another device', onPressed: widget.onChangeDevice, icon: const Icon(Icons.radar)),
                  IconButton(tooltip: 'Settings', onPressed: _settings, icon: const Icon(Icons.tune)),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        button: true,
                        label: 'Unlock the door',
                        child: GestureDetector(
                          key: const Key('unlock-button'),
                          onTap: _unlock,
                          child: AnimatedBuilder(
                            animation: _ring,
                            builder: (context, _) => CustomPaint(
                              size: const Size.square(240),
                              painter: _RingPainter(
                                progress: open ? 1 - _ring.value : 0,
                                color: ringColor,
                                track: scheme.surfaceContainerHighest,
                              ),
                              child: SizedBox.square(
                                dimension: 240,
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: 184,
                                    height: 184,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: open ? scheme.tertiaryContainer : scheme.primaryContainer,
                                    ),
                                    child: _phase == _Phase.opening
                                        ? const Padding(padding: EdgeInsets.all(70), child: CircularProgressIndicator(strokeWidth: 3))
                                        : Icon(
                                            open ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                                            size: 84,
                                            color: open ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _phase == _Phase.idle && _message.isEmpty ? 'Tap to unlock' : _message,
                        key: const Key('status'),
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(color: problem ? scheme.error : null),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Opens for ${widget.seconds} seconds, then locks by itself.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.track});

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(6);
    canvas.drawArc(
      arc,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        arc,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 8
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.device, required this.seconds});

  final Device device;
  final int seconds;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late int _seconds = widget.seconds;
  late final TextEditingController _key = TextEditingController(text: widget.device.key == 0 ? '' : '${widget.device.key}');

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _done() {
    final key = int.tryParse(_key.text.trim()) ?? 0;
    Navigator.pop(context, (widget.device.copyWith(key: key), _seconds));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Keep the door open for', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 3, label: Text('3 s')),
              ButtonSegment(value: 5, label: Text('5 s')),
              ButtonSegment(value: 10, label: Text('10 s')),
            ],
            selected: {_seconds},
            onSelectionChanged: (s) => setState(() => _seconds = s.single),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _key,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Comm key (leave empty if none)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context, null),
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(onPressed: _done, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
