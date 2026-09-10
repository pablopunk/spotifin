import 'dart:math' as math;

double volumeFromSlider(double position) {
  final value = position.clamp(0.0, 1.0);
  return value * value;
}

double sliderFromVolume(double volume) {
  final value = volume.clamp(0.0, 1.0);
  return math.sqrt(value);
}
