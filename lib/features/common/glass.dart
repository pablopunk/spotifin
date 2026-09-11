import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';

abstract final class SpotifinGlass {
  static const _appleOpacityScale = .4;

  static final theme = GlassThemeData.simple(
    blur: 8,
    thickness: 28,
    quality: GlassQuality.standard,
    brightness: Brightness.dark,
  );

  static LiquidGlassSettings settings(double opacity) => LiquidGlassSettings(
    blur: 8,
    thickness: 28,
    backerColor: SpotifinColors.voidBlack.withValues(
      alpha: effectiveOpacity(opacity),
    ),
  );

  static double effectiveOpacity(double opacity) {
    final appleRenderer =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return appleRenderer ? opacity * _appleOpacityScale : opacity;
  }
}

final glassEffectsProvider = Provider<bool>(
  (ref) =>
      ref.watch(appControllerProvider.select((state) => state.glassEffects)),
);

final glassOpacityProvider = Provider<double>(
  (ref) =>
      ref.watch(appControllerProvider.select((state) => state.glassOpacity)),
);
