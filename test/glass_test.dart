import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/features/common/glass.dart';

void main() {
  test('glass appearance defaults and copy independently', () {
    const state = AppState();

    expect(state.glassEffects, isTrue);
    expect(state.glassOpacity, .8);

    final changed = state.copyWith(glassEffects: false, glassOpacity: .7);
    expect(changed.glassEffects, isFalse);
    expect(changed.glassOpacity, .7);
  });

  test('Apple glass opacity is calibrated for its stronger renderer', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(SpotifinGlass.effectiveOpacity(.8), closeTo(.32, .001));

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(SpotifinGlass.effectiveOpacity(.8), .8);
  });
}
