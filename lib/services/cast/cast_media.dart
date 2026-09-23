/// Payload handed to a Chromecast receiver for one audio track.
///
/// Mirrors what the Jellyfin Web Receiver needs: a stream URL it can fetch
/// directly, a MIME type, human metadata, artwork, duration, start position,
/// and opaque Jellyfin ids in `customData` (never credentials).
class CastTrackPayload {
  const CastTrackPayload({
    required this.contentId,
    required this.contentUrl,
    required this.contentType,
    required this.title,
    required this.artist,
    required this.album,
    this.artworkUrl,
    required this.duration,
    required this.startPosition,
    required this.itemId,
    this.playlistItemId,
  });

  final String contentId;
  final Uri contentUrl;
  final String contentType;
  final String title;
  final String artist;
  final String album;
  final Uri? artworkUrl;
  final Duration duration;
  final Duration startPosition;
  final String itemId;
  final String? playlistItemId;

  /// Opaque ids forwarded to the receiver. No tokens or passwords.
  Map<String, dynamic> get customData => {
    'itemId': itemId,
    if (playlistItemId != null) 'playlistItemId': playlistItemId,
  };
}
