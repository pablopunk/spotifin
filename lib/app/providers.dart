import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/jellyfin/jellyfin_client.dart';
import '../services/jellyfin/session_store.dart';
import '../services/playback/playback_service.dart';
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

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => const SessionStore(FlutterSecureStorage()),
);

final playbackProvider = Provider<PlaybackService>((ref) {
  final service = PlaybackService(ref.watch(jellyfinClientProvider));
  ref.onDispose(service.dispose);
  return service;
});

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);
