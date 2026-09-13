import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app/app.dart';
import 'features/common/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // just_audio has no native Linux/Windows implementation; register the
  // media_kit backend before JustAudioBackground wraps the platform instance.
  JustAudioMediaKit.title = 'Spotifin';
  JustAudioMediaKit.ensureInitialized();
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  PaintingBinding.instance.imageCache
    ..maximumSize = 300
    ..maximumSizeBytes = 64 << 20;
  await JustAudioBackground.init(
    androidNotificationChannelId: 'app.spotifin.audio',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
  );
  await LiquidGlassWidgets.initialize();
  runApp(
    LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      adaptiveQuality: true,
      theme: SpotifinGlass.theme,
      child: const ProviderScope(child: SpotifinApp()),
    ),
  );
}
