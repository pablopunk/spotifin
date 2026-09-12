import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/jellyfin/jellyfin_client.dart';
import '../services/downtify/downtify_client.dart';
import '../services/downtify/downtify_store.dart';
import '../services/jellyfin/session_store.dart';
import '../services/lyrics/lyrics_service.dart';
import '../services/downloads/download_service.dart';
import '../services/playback/playback_service.dart';
import '../services/playback/remote_session_service.dart';
import '../platform/download_store.dart';
import '../platform/artwork_store.dart';
import '../platform/carplay_service.dart';
import '../storage/database.dart';
import 'state/app_controller.dart';
import 'state/downtify_controller.dart';
import 'state/player_panel_controller.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final allTracksStreamProvider = Provider<Stream<List<Track>>>(
  (ref) => ref.watch(databaseProvider).watchTracks(),
);

final tracksByDateAddedStreamProvider = Provider<Stream<List<Track>>>(
  (ref) => ref.watch(databaseProvider).watchTracksByDateAdded(),
);

final playlistsStreamProvider = Provider<Stream<List<Playlist>>>(
  (ref) => ref.watch(databaseProvider).watchPlaylists(),
);

final downloadsStreamProvider = Provider<Stream<List<Download>>>(
  (ref) => ref.watch(databaseProvider).watchDownloads(),
);

final albumDatesStreamProvider = Provider<Stream<Map<String, DateTime>>>(
  (ref) => ref.watch(databaseProvider).watchAlbumDates(),
);

final jellyfinClientProvider = Provider<JellyfinClient>((ref) {
  final client = JellyfinClient();
  ref.onDispose(client.close);
  return client;
});

final downtifyClientProvider = Provider<DowntifyClient>((ref) {
  final client = DowntifyClient();
  ref.onDispose(client.close);
  return client;
});

final downtifyStoreProvider = Provider<DowntifyStore>(
  (ref) => const DowntifyStore(),
);

final downtifyControllerProvider =
    NotifierProvider<DowntifyController, DowntifyState>(DowntifyController.new);

final lyricsProvider = Provider<LyricsService>(
  (ref) => LyricsService(ref.watch(jellyfinClientProvider)),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => const SessionStore(
    FlutterSecureStorage(
      mOptions: MacOsOptions(
        accountName: 'com.pablopunk.spotifin.session',
        usesDataProtectionKeychain: false,
      ),
    ),
  ),
);

final downloadProvider = Provider<DownloadService>((ref) {
  final service = DownloadService(
    ref.watch(databaseProvider),
    ref.watch(jellyfinClientProvider),
    DownloadStore(),
    ref.watch(artworkStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final artworkStoreProvider = Provider<ArtworkStore>((ref) {
  final store = ArtworkStore();
  ref.onDispose(store.dispose);
  return store;
});

final downloadStatusesProvider = StreamProvider<Map<String, String>>((ref) {
  return ref
      .watch(databaseProvider)
      .watchDownloads()
      .map((rows) => {for (final row in rows) row.trackId: row.status});
});

final playbackProvider = Provider<PlaybackService>((ref) {
  final service = PlaybackService(
    ref.watch(jellyfinClientProvider),
    ref.watch(downloadProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final remoteSessionProvider = Provider<RemoteSessionService>((ref) {
  final service = RemoteSessionService(
    ref.watch(jellyfinClientProvider),
    ref.watch(playbackProvider),
    ref.watch(databaseProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

final playerPanelProvider =
    NotifierProvider<PlayerPanelController, PlayerPanelState>(
      PlayerPanelController.new,
    );

final carPlayProvider = Provider<CarPlayService>((ref) => CarPlayService());
