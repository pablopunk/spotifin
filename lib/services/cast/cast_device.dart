/// Chromecast target discovered on the local network.
///
/// Pure value object decoupled from `flutter_chrome_cast` plugin types so
/// business logic and tests never touch the native SDK directly. The real
/// sender ([ChromeCastSender]) maps `GoogleCastDevice` into this model.
class CastDevice {
  const CastDevice({
    required this.id,
    required this.friendlyName,
    this.modelName,
  });

  final String id;
  final String friendlyName;
  final String? modelName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CastDevice && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CastDevice($friendlyName)';
}
