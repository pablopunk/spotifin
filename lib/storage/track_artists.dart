import 'dart:convert';

import 'database.dart';

class TrackArtist {
  const TrackArtist({required this.name, this.id});

  final String name;
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is TrackArtist && other.name == name && other.id == id;

  @override
  int get hashCode => Object.hash(name, id);
}

extension TrackArtistCredits on Track {
  List<TrackArtist> get artistCredits => parseArtistItems(artistItems, artist);
}

String encodeArtistItems(Iterable<TrackArtist> artists) => jsonEncode([
  for (final artist in artists) {'id': artist.id, 'name': artist.name},
]);

List<TrackArtist> parseArtistItems(String encoded, String fallbackArtist) {
  final decoded = _decodeList(encoded);
  final items = [
    for (final entry in decoded)
      if (entry is Map &&
          entry['name'] is String &&
          (entry['name'] as String).trim().isNotEmpty)
        TrackArtist(
          name: (entry['name'] as String).trim(),
          id: entry['id'] is String ? entry['id'] as String : null,
        ),
  ];
  if (items.isNotEmpty) return items;

  final names = _splitNames(fallbackArtist);
  final legacyIds = [
    for (final entry in decoded)
      if (entry is String && entry.isNotEmpty) entry,
  ];
  if (legacyIds.length == names.length) {
    return [
      for (var index = 0; index < legacyIds.length; index++)
        TrackArtist(id: legacyIds[index], name: names[index]),
    ];
  }
  return [for (final name in names) TrackArtist(name: name)];
}

bool includesArtist(Track track, TrackArtist artist) => track.artistCredits.any(
  (credit) => artist.id != null && credit.id != null
      ? credit.id == artist.id
      : credit.name == artist.name,
);

List<Object?> _decodeList(String encoded) {
  try {
    final decoded = jsonDecode(encoded);
    return decoded is List ? decoded : const [];
  } on FormatException {
    return const [];
  }
}

List<String> _splitNames(String artist) => artist
    .split(', ')
    .map((name) => name.trim())
    .where((name) => name.isNotEmpty)
    .toList(growable: false);
