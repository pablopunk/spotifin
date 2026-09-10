import 'dart:math' as math;

const _minimumDecibels = -60.0;

double volumeFromSlider(double position) {
  if (position <= 0) return 0;
  final decibels = _minimumDecibels * (1 - position.clamp(0.0, 1.0));
  return math.pow(10, decibels / 20).toDouble();
}

double sliderFromVolume(double volume) {
  if (volume <= 0) return 0;
  final decibels = 20 * math.log(volume.clamp(0.0, 1.0)) / math.ln10;
  return (1 - decibels / _minimumDecibels).clamp(0.0, 1.0);
}
