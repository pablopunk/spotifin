import 'dart:math' as math;

/// Local playback maps the linear UI slider onto a quadratic gain curve so
/// low slider positions stay usable. Cast volume is linear end to end; the
/// slider value is sent unchanged.
double volumeFromSlider(double position) {
  final value = position.clamp(0.0, 1.0);
  return value * value;
}

double sliderFromVolume(double volume) {
  final value = volume.clamp(0.0, 1.0);
  return math.sqrt(value);
}
