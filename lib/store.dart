import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device.dart';

class SavedState {
  const SavedState({this.device, this.seconds = 3});
  final Device? device;
  final int seconds;
}

/// Remembers the chosen door machine and how long the relay stays open.
/// The comm key is kept here too for now; a keychain-backed store is a later step.
class Store {
  static const _deviceKey = 'device';
  static const _secondsKey = 'seconds';

  Future<SavedState> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_deviceKey);
      final device = raw == null ? null : Device.fromJson(jsonDecode(raw));
      return SavedState(device: device, seconds: prefs.getInt(_secondsKey) ?? 3);
    } catch (_) {
      return const SavedState();
    }
  }

  Future<void> save({Device? device, required int seconds}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (device == null) {
        await prefs.remove(_deviceKey);
      } else {
        await prefs.setString(_deviceKey, jsonEncode(device.toJson()));
      }
      await prefs.setInt(_secondsKey, seconds);
    } catch (_) {
      // storage is a convenience: the app still works without it
    }
  }
}
