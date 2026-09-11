import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/providers.dart';

abstract final class SpotifinGlass {
  static final theme = GlassThemeData.simple(
    blur: 8,
    thickness: 28,
    quality: GlassQuality.standard,
    brightness: Brightness.dark,
  );
}

final glassEffectsProvider = Provider<bool>(
  (ref) =>
      ref.watch(appControllerProvider.select((state) => state.glassEffects)),
);
