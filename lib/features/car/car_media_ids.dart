import '../../platform/safe_path_segment.dart';

String carPlaylistId(String raw) =>
    raw.isEmpty ? 'car:unknown' : 'car:playlist:${safePathSegment(raw)}';

String carArtistId(String raw) =>
    raw.isEmpty ? 'car:unknown' : 'car:artist:${safePathSegment(raw)}';

String carAlbumId(String raw) =>
    raw.isEmpty ? 'car:unknown' : 'car:album:${safePathSegment(raw)}';

String carTrackId(String raw) =>
    raw.isEmpty ? 'car:unknown' : 'car:track:${safePathSegment(raw)}';
