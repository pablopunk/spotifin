import '../search/search_text.dart';
import 'downtify_client.dart';
import 'downtify_models.dart';

class DowntifyCollectionSearch {
  const DowntifyCollectionSearch.artist(this.artist) : album = null;

  const DowntifyCollectionSearch.album({
    required String this.album,
    required this.artist,
  });

  final String artist;
  final String? album;

  String get query => [artist, ?album].join(' ');

  Future<List<DowntifySong>> load(DowntifyClient client, String origin) {
    final album = this.album;
    return album == null
        ? _loadArtist(client, origin)
        : _loadAlbum(client, origin, album);
  }

  Future<List<DowntifySong>> _loadArtist(
    DowntifyClient client,
    String origin,
  ) async {
    final (artists, songs) = await (
      client.searchArtists(origin, artist),
      client.search(origin, artist),
    ).wait;
    final match = artists.where((found) => _sameName(found.name, artist));
    final topSongs = match.isEmpty
        ? const <DowntifySong>[]
        : await client.artistTopSongs(origin, match.first.id);
    return _withoutRepeatedTitles([...topSongs, ...songs.where(_credits)]);
  }

  Future<List<DowntifySong>> _loadAlbum(
    DowntifyClient client,
    String origin,
    String album,
  ) async {
    final albums = await client.searchAlbums(origin, query);
    final match = albums.where(
      (found) =>
          _sameName(found.name, album) &&
          found.artists.any((name) => _sameName(name, artist)),
    );
    if (match.isNotEmpty) return client.albumSongs(origin, match.first);
    final songs = await client.search(origin, query);
    return songs.where(_credits).toList();
  }

  bool _credits(DowntifySong song) =>
      song.artists.any((name) => _sameName(name, artist));

  static List<DowntifySong> _withoutRepeatedTitles(List<DowntifySong> songs) {
    final seen = <String>{};
    return songs.where((song) => seen.add(_normalize(song.name))).toList();
  }

  static bool _sameName(String a, String b) => _normalize(a) == _normalize(b);

  static String _normalize(String value) => normalizeSearchText(value).trim();

  @override
  bool operator ==(Object other) =>
      other is DowntifyCollectionSearch &&
      other.artist == artist &&
      other.album == album;

  @override
  int get hashCode => Object.hash(artist, album);
}
