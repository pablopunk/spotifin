import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/features.dart';

void main() {
  test('build uses the selected Downtify feature state', () {
    const expected = bool.fromEnvironment(
      'SPOTIFIN_EXPECT_DOWNTIFY',
      defaultValue: true,
    );
    expect(AppFeatures.downtify, expected);
  });
}
