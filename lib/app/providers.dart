import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/jellyfin/jellyfin_client.dart';
import '../services/downtify/downtify_client.dart';
import '../services/downtify/downtify_store.dart';
import '../services/jellyfin/secure_storage_config.dart';
import '../services/jellyfin/session_store.dart';
import '../services/lyrics/lyrics_service.dart';
import '../services/downloads/download_service.dart';
import '../services/playback/playback_service.dart';
import '../services/playback/remote_session_service.dart';
import '../services/cast/cast_controller.dart';
import '../services/cast/chrome_cast_sender.dart';
import '../services/cast/jellyfin_cast_adapter.dart';
import '../services/cast/playback_service_cast_source.dart';
import '../services/updates/update_controller.dart';
import '../services/updates/update_service.dart';
import '../features/car/car_controller.dart';
import '../platform/download_store.dart';
import '../platform/artwork_store.dart';
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

/// Cached Jellyfin Recently Played history (see `watchRecentlyPlayed`).
///
/// Per AGENTS.md, drift `watch*()` streams are exposed here as providers;
/// widgets must watch this provider instead of calling `database.*` in
/// `build`.
final recentlyPlayedStreamProvider = Provider<Stream<List<Track>>>(
  (ref) => ref.watch(databaseProvider).watchRecentlyPlayed(),
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

final sessionSecureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => buildSessionSecureStorage(),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(ref.watch(sessionSecureStorageProvider)),
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

final castControllerProvider = Provider<CastController>((ref) {
  final controller = CastController(
    playback: PlaybackServiceCastSource(ref.watch(playbackProvider)),
    adapter: JellyfinCastAdapter(ref.watch(jellyfinClientProvider)),
    sender: ChromeCastSender(),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

final playerPanelProvider =
    NotifierProvider<PlayerPanelController, PlayerPanelState>(
      PlayerPanelController.new,
    );

final carControllerProvider = NotifierProvider<CarController, CarState>(
  CarController.new,
);

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
  ref.onDispose(service.close);
  return service;
});

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
