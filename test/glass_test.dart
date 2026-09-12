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

  test('glass opacity is calibrated for each renderer', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(SpotifinGlass.effectiveOpacity(.8), closeTo(.32, .001));

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(SpotifinGlass.effectiveOpacity(0), .35);
    expect(SpotifinGlass.effectiveOpacity(.8), .8);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(SpotifinGlass.effectiveOpacity(.8), .8);
  });

  test('fallback renderers use shader tint so grouped glass is opaque', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final settings = SpotifinGlass.settings(0);

    expect(settings.glassColor.a, closeTo(.35, .001));
    expect(settings.backerColor, isNull);
  });

  test('glass edge optics stay subdued', () {
    final settings = SpotifinGlass.settings(.8);

    expect(settings.chromaticAberration, 0);
    expect(settings.lightIntensity, lessThan(.1));
    expect(settings.fresnelStrength, lessThan(.1));
    expect(settings.refractiveIndex, 1.05);
    expect(settings.glowIntensity, 0);
    expect(settings.shadowElevation, 0);
  });
}
