import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'app.spotifin.audio',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
  );
  runApp(const ProviderScope(child: SpotifinApp()));
}
