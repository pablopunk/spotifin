import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/player/volume_scale.dart';

void main() {
  test('uses a quadratic volume curve', () {
    expect(volumeFromSlider(0), 0);
    expect(volumeFromSlider(.5), .25);
    expect(volumeFromSlider(1), 1);
  });

  test('converts player volume back to the slider position', () {
    for (final position in [0.0, .25, .5, .75, 1.0]) {
      expect(
        sliderFromVolume(volumeFromSlider(position)),
        closeTo(position, 1e-9),
      );
    }
  });
}
