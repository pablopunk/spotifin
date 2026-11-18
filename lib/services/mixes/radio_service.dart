import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';
import 'radio_generator.dart';

class RadioService {
  RadioService(this._client, this._database);

  final JellyfinClient _client;
  final AppDatabase _database;

  Future<List<Track>> queueFor(Track seed, JellyfinSession? session) async {
    final catalog = await _database.allTracks();
    final instantMix = _libraryTracksInOrder(
      await _instantMixIdsOrEmptyWhenOffline(seed, session),
      catalog,
    ).where((track) => track.id != seed.id);
    if (instantMix.isNotEmpty) return [seed, ...instantMix];
    return const RadioGenerator().generate(seed, catalog);
  }

  Future<List<String>> _instantMixIdsOrEmptyWhenOffline(
    Track seed,
    JellyfinSession? session,
  ) async {
    if (session == null) return const [];
    try {
      return await _client.fetchInstantMixTrackIds(session, seed.id);
    } on Object {
      return const [];
    }
  }

  List<Track> _libraryTracksInOrder(List<String> ids, List<Track> catalog) {
    final byId = {for (final track in catalog) track.id: track};
    return [for (final id in ids) ?byId[id]];
  }
}
