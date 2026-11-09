/// A ZK door machine found on the LAN (or restored from storage).
class Device {
  const Device({required this.ip, this.port = 4370, this.serial, this.name, this.key = 0});

  final String ip;
  final int port;
  final String? serial;
  final String? name;
  final int key;

  String get title => (name == null || name!.isEmpty) ? 'Door machine' : name!;

  Device copyWith({int? key, String? serial, String? name}) =>
      Device(ip: ip, port: port, serial: serial ?? this.serial, name: name ?? this.name, key: key ?? this.key);

  Map<String, Object?> toJson() => {'ip': ip, 'port': port, 'serial': serial, 'name': name, 'key': key};

  static Device? fromJson(Object? json) {
    if (json is! Map || json['ip'] is! String) return null;
    return Device(
      ip: json['ip'] as String,
      port: (json['port'] as int?) ?? 4370,
      serial: json['serial'] as String?,
      name: json['name'] as String?,
      key: (json['key'] as int?) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Device && other.ip == ip && other.port == port && other.serial == serial && other.key == key;

  @override
  int get hashCode => Object.hash(ip, port, serial, key);
}
