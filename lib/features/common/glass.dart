import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';

abstract final class SpotifinGlass {
  static const _appleOpacityScale = .4;
  static const _fallbackMinimumOpacity = .35;
  static const maxOpacity = .8;

  static final theme = GlassThemeData.simple(
    blur: 8,
    thickness: 28,
    quality: GlassQuality.standard,
    brightness: Brightness.dark,
  );

  static LiquidGlassSettings settings(double opacity) {
    final alpha = effectiveOpacity(opacity);
    final fallbackRenderer = _usesFallbackRenderer;
    return LiquidGlassSettings(
      blur: 8,
      thickness: 28,
      chromaticAberration: 0,
      lightIntensity: .08,
      fresnelStrength: .08,
      refractiveIndex: 1.05,
      glowIntensity: 0,
      shadowElevation: 0,
      glassColor: SpotifinColors.voidBlack.withValues(
        alpha: fallbackRenderer ? alpha : 0,
      ),
      backerColor: fallbackRenderer
          ? null
          : SpotifinColors.voidBlack.withValues(alpha: alpha),
    );
  }

  static double effectiveOpacity(double opacity) {
    if (_usesAppleRenderer) return opacity * _appleOpacityScale;
    if (_usesFallbackRenderer) {
      final position = (opacity / maxOpacity).clamp(0.0, 1.0);
      return _fallbackMinimumOpacity +
          position * (maxOpacity - _fallbackMinimumOpacity);
    }
    return opacity;
  }

  static bool get _usesAppleRenderer =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get _usesFallbackRenderer =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}

final glassEffectsProvider = Provider<bool>(
  (ref) =>
      ref.watch(appControllerProvider.select((state) => state.glassEffects)),
);

final glassOpacityProvider = Provider<double>(
  (ref) =>
      ref.watch(appControllerProvider.select((state) => state.glassOpacity)),
);
