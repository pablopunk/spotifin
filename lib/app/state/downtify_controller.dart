import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/downtify/downtify_client.dart';
import '../../services/downtify/downtify_matcher.dart';
import '../../services/downtify/downtify_models.dart';
import '../../services/jellyfin/jellyfin_client.dart';
import '../../storage/database.dart';
import '../providers.dart';

enum DowntifyAvailability { loading, unconfigured, available, unavailable }

class DowntifyNotice {
  const DowntifyNotice(this.id, this.message, {this.error = false});

  final String id;
  final String message;
  final bool error;
}

class DowntifyState {
  const DowntifyState({
    this.availability = DowntifyAvailability.loading,
    this.serverUrl,
    this.version,
    this.results = const [],
    this.searching = false,
    this.imports = const [],
    this.notices = const [],
  });

  final DowntifyAvailability availability;
  final String? serverUrl;
  final String? version;
  final List<DowntifySong> results;
  final bool searching;
  final List<DowntifyImport> imports;
  final List<DowntifyNotice> notices;

  bool get available => availability == DowntifyAvailability.available;

  DowntifyState copyWith({
    DowntifyAvailability? availability,
    String? serverUrl,
    String? version,
    List<DowntifySong>? results,
    bool? searching,
    List<DowntifyImport>? imports,
    List<DowntifyNotice>? notices,
    bool clearServer = false,
  }) => DowntifyState(
    availability: availability ?? this.availability,
    serverUrl: clearServer ? null : serverUrl ?? this.serverUrl,
    version: clearServer ? null : version ?? this.version,
    results: results ?? this.results,
    searching: searching ?? this.searching,
    imports: imports ?? this.imports,
    notices: notices ?? this.notices,
  );
}

class DowntifyController extends Notifier<DowntifyState> {
  Timer? _searchTimer;
  Timer? _pollTimer;
  Timer? _scanTimer;
  int _searchGeneration = 0;
  bool _polling = false;
  bool _refreshingJellyfin = false;
  DateTime? _lastJellyfinRefresh;

  @override
  DowntifyState build() {
    ref.onDispose(() {
      _searchTimer?.cancel();
      _pollTimer?.cancel();
      _scanTimer?.cancel();
    });
    Future.microtask(_initialize);
    return const DowntifyState();
  }

  Future<void> _initialize() async {
    final serverUrl = await ref.read(downtifyStoreProvider).loadServerUrl();
    if (serverUrl == null) {
      state = state.copyWith(
        availability: DowntifyAvailability.unconfigured,
        clearServer: true,
      );
      return;
    }
    await _loadImports();
    await _connect(serverUrl);
  }

  Future<void> configure(String value) async {
    final serverUrl = DowntifyClient.normalizeServerUrl(value);
    state = state.copyWith(
      availability: DowntifyAvailability.loading,
      serverUrl: serverUrl,
      results: const [],
    );
    try {
      final version = await ref
          .read(downtifyClientProvider)
          .fetchVersion(serverUrl);
      await ref.read(downtifyStoreProvider).saveServerUrl(serverUrl);
      state = state.copyWith(
        availability: DowntifyAvailability.available,
        serverUrl: serverUrl,
        version: version,
      );
      await _loadImports();
      _startPolling();
    } catch (_) {
      state = state.copyWith(availability: DowntifyAvailability.unavailable);
      rethrow;
    }
  }

  Future<void> reconnect() async {
    final serverUrl = state.serverUrl;
    if (serverUrl != null) await _connect(serverUrl);
  }

  Future<void> removeConfiguration() async {
    _searchTimer?.cancel();
    _pollTimer?.cancel();
    _scanTimer?.cancel();
    await ref.read(downtifyStoreProvider).clearServerUrl();
    state = const DowntifyState(
      availability: DowntifyAvailability.unconfigured,
    );
  }

  void search(String query) {
    _searchTimer?.cancel();
    final trimmed = query.trim();
    final generation = ++_searchGeneration;
    if (!state.available || trimmed.length < 2) {
      state = state.copyWith(results: const [], searching: false);
      return;
    }
    state = state.copyWith(searching: true);
    _searchTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await ref
            .read(downtifyClientProvider)
            .search(state.serverUrl!, trimmed);
        if (generation != _searchGeneration) return;
        state = state.copyWith(results: results, searching: false);
      } catch (_) {
        if (generation != _searchGeneration) return;
        state = state.copyWith(
          availability: DowntifyAvailability.unavailable,
          results: const [],
          searching: false,
        );
      }
    });
  }

  Future<void> enqueue(DowntifySong song) async {
    final session = ref.read(appControllerProvider).session;
    final serverUrl = state.serverUrl;
    if (session == null || serverUrl == null || importFor(song.id) != null) {
      return;
    }
    final now = DateTime.now();
    final id = '${session.serverId}:${session.userId}:${song.id}';
    await _save(
      DowntifyImport(
        id: id,
        jellyfinServerId: session.serverId,
        jellyfinUserId: session.userId,
        downtifyUrl: serverUrl,
        externalSongId: song.id,
        jobId: null,
        songJson: jsonEncode(song.raw),
        status: 'submitting',
        progress: 0,
        message: '',
        filename: null,
        matchedTrackId: null,
        messageShown: false,
        createdAt: now,
        updatedAt: now,
      ),
    );
    try {
      final jobId = await ref
          .read(downtifyClientProvider)
          .enqueue(serverUrl, song);
      await _update(id, status: 'queued', jobId: jobId);
      _startPolling();
      await poll();
    } catch (error) {
      await _update(id, status: 'downloadFailed', message: error.toString());
      _addNotice('Import failed for ${song.name}.', error: true);
    }
  }

  DowntifyImport? importFor(String externalSongId) {
    final session = ref.read(appControllerProvider).session;
    if (session == null) return null;
    return state.imports.where((item) {
      return item.externalSongId == externalSongId &&
          item.jellyfinServerId == session.serverId &&
          item.jellyfinUserId == session.userId;
    }).firstOrNull;
  }

  Future<void> retry(DowntifyImport item) async {
    final song = _songFromImport(item);
    await ref.read(databaseProvider).removeDowntifyImport(item.id);
    await _loadImports();
    await enqueue(song);
  }

  Future<void> dismiss(DowntifyImport item) async {
    await ref.read(databaseProvider).removeDowntifyImport(item.id);
    await _loadImports();
  }

  void dismissNotice(String id) {
    state = state.copyWith(
      notices: state.notices.where((notice) => notice.id != id).toList(),
    );
  }

  Future<void> poll() async {
    if (_polling || !state.available || state.serverUrl == null) return;
    _polling = true;
    try {
      final remote = await ref
          .read(downtifyClientProvider)
          .fetchQueue(state.serverUrl!);
      final byId = {for (final job in remote) job.song.id: job};
      for (final item in [...state.imports]) {
        final job = byId[item.jobId ?? item.externalSongId];
        if (job == null) continue;
        if (job.status == DowntifyJobStatus.error) {
          await _update(
            item.id,
            status: 'downloadFailed',
            progress: job.progress,
            message: job.message,
          );
          _addNotice('Import failed for ${job.song.name}.', error: true);
        } else if (job.status == DowntifyJobStatus.done) {
          if (item.status == 'queued' || item.status == 'downloading') {
            await _update(
              item.id,
              status: 'requestingScan',
              progress: 100,
              filename: job.filename,
            );
            _scheduleLibraryScan();
          }
        } else if (job.status == DowntifyJobStatus.downloading ||
            job.status == DowntifyJobStatus.queued) {
          await _update(
            item.id,
            status: job.status.name,
            progress: job.progress,
            message: job.message,
          );
        }
      }
      await _refreshWaitingImports();
    } catch (_) {
      state = state.copyWith(availability: DowntifyAvailability.unavailable);
      _pollTimer?.cancel();
    } finally {
      _polling = false;
    }
  }

  Future<void> _connect(String serverUrl) async {
    state = state.copyWith(
      availability: DowntifyAvailability.loading,
      serverUrl: serverUrl,
    );
    try {
      final version = await ref
          .read(downtifyClientProvider)
          .fetchVersion(serverUrl);
      state = state.copyWith(
        availability: DowntifyAvailability.available,
        version: version,
      );
      _startPolling();
      await poll();
    } catch (_) {
      state = state.copyWith(availability: DowntifyAvailability.unavailable);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  void _scheduleLibraryScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 1), _requestLibraryScan);
  }

  Future<void> _requestLibraryScan() async {
    final session = ref.read(appControllerProvider).session;
    if (session == null) return;
    try {
      await ref.read(jellyfinClientProvider).requestLibraryRefresh(session);
      for (final item in [...state.imports]) {
        if (item.status == 'requestingScan') {
          await _update(item.id, status: 'waitingForJellyfin');
        }
      }
    } on JellyfinException catch (error) {
      final denied = error.statusCode == 403;
      for (final item in [...state.imports]) {
        if (item.status == 'requestingScan') {
          await _update(
            item.id,
            status: denied ? 'scanDenied' : 'waitingForJellyfin',
            message: denied
                ? 'Waiting for Jellyfin’s scheduled library scan.'
                : error.toString(),
          );
        }
      }
      if (denied) {
        _addNotice(
          'Jellyfin did not allow an instant scan; the song will appear after its next scheduled scan.',
        );
      }
    }
  }

  Future<void> _refreshWaitingImports() async {
    if (_refreshingJellyfin) return;
    final waiting = state.imports.where((item) {
      return const {'waitingForJellyfin', 'scanDenied'}.contains(item.status);
    }).toList();
    if (waiting.isEmpty) return;
    final now = DateTime.now();
    if (_lastJellyfinRefresh != null &&
        now.difference(_lastJellyfinRefresh!) < const Duration(seconds: 10)) {
      return;
    }
    _lastJellyfinRefresh = now;
    _refreshingJellyfin = true;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .refresh(silent: true, force: true);
      final tracks = await ref.read(databaseProvider).allTracks();
      for (final item in waiting) {
        final song = _songFromImport(item);
        final match = const DowntifyMatcher().findMatch(song, tracks);
        if (match != null) {
          await _update(
            item.id,
            status: 'imported',
            matchedTrackId: match.id,
            progress: 100,
          );
          _addNotice('${song.name} is now available in your library.');
        } else if (DateTime.now().difference(item.createdAt) >
            const Duration(minutes: 15)) {
          await _update(
            item.id,
            status: 'importTimedOut',
            message: 'Jellyfin has not found this song yet.',
          );
          _addNotice('Jellyfin has not found ${song.name} yet.', error: true);
        }
      }
    } finally {
      _refreshingJellyfin = false;
    }
  }

  Future<void> _loadImports() async {
    final session = ref.read(appControllerProvider).session;
    if (session == null) return;
    final imports = await ref
        .read(databaseProvider)
        .getDowntifyImports(session.serverId, session.userId);
    state = state.copyWith(imports: imports);
  }

  Future<void> _save(DowntifyImport item) async {
    await ref.read(databaseProvider).putDowntifyImport(item.toCompanion(true));
    await _loadImports();
  }

  Future<void> _update(
    String id, {
    String? status,
    String? jobId,
    double? progress,
    String? message,
    String? filename,
    String? matchedTrackId,
  }) async {
    final item = state.imports
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (item == null) return;
    await _save(
      item.copyWith(
        status: status ?? item.status,
        jobId: Value(jobId ?? item.jobId),
        progress: progress ?? item.progress,
        message: message ?? item.message,
        filename: Value(filename ?? item.filename),
        matchedTrackId: Value(matchedTrackId ?? item.matchedTrackId),
        updatedAt: DateTime.now(),
      ),
    );
  }

  DowntifySong _songFromImport(DowntifyImport item) =>
      DowntifySong.fromJson(jsonDecode(item.songJson) as Map<String, dynamic>);

  void _addNotice(String message, {bool error = false}) {
    final notice = DowntifyNotice(
      DateTime.now().microsecondsSinceEpoch.toString(),
      message,
      error: error,
    );
    state = state.copyWith(notices: [...state.notices, notice]);
  }
}
