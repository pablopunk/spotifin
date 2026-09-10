import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/jellyfin/jellyfin_client.dart';
import '../services/jellyfin/session_store.dart';
import '../services/lyrics/lyrics_service.dart';
import '../services/downloads/download_service.dart';
import '../services/playback/playback_service.dart';
import '../platform/download_store.dart';
import '../platform/carplay_service.dart';
import '../storage/database.dart';
import 'state/app_controller.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final jellyfinClientProvider = Provider<JellyfinClient>(
  (ref) => JellyfinClient(),
);

final lyricsProvider = Provider<LyricsService>(
  (ref) => LyricsService(ref.watch(jellyfinClientProvider)),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => const SessionStore(FlutterSecureStorage()),
);

final downloadProvider = Provider<DownloadService>((ref) {
  final service = DownloadService(
    ref.watch(databaseProvider),
    ref.watch(jellyfinClientProvider),
    DownloadStore(),
  );
  ref.onDispose(service.dispose);
  return service;
});

final playbackProvider = Provider<PlaybackService>((ref) {
  final service = PlaybackService(
    ref.watch(jellyfinClientProvider),
    ref.watch(downloadProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

final carPlayProvider = Provider<CarPlayService>((ref) => CarPlayService());
