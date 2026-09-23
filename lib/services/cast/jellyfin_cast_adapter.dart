import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';
import 'cast_media.dart';

/// Builds Chromecast payloads from Jellyfin library data.
///
/// Reuses [JellyfinClient.streamUri] / [imageUri] so the receiver fetches
/// exactly the same bytes the phone would stream. No parallel media backend:
/// the Cast receiver is a thin Jellyfin client and the sender only hands it
/// URLs plus display metadata.
///
/// Security note: stream/artwork URLs carry `api_key` as a query parameter
/// (same as Jellyfin web/Android senders). The user password is never placed
/// on the receiver and tokens are never written to logs (see `redactSecrets`).
class JellyfinCastAdapter {
  const JellyfinCastAdapter(this._client);

  final JellyfinClient _client;

  /// Jellyfin Web Receiver app IDs shipped with the server.
  ///
  /// `F007D354` is the production receiver registered with Google;
  /// `6F511C87` tracks the receiver `master` branch. Resolved from the
  /// server `CastReceiverApplications` model where available; these pinned
  /// values are the fallback (see jellyfin-web `chromecastPlayer/plugin.js`
  /// and server `system.xml` defaults).
  static const String stableReceiverAppId = 'F007D354';
  static const String unstableReceiverAppId = '6F511C87';

  static String receiverAppId({bool unstable = false}) =>
      unstable ? unstableReceiverAppId : stableReceiverAppId;

  /// MIME type for a Jellyfin audio container.
  ///
  /// Cast receivers accept common audio containers directly. Exotic
  /// containers fall back to `audio/mpeg` and the controller retries the
  /// item with the AAC (`small`) profile when the receiver rejects it.
  static String contentTypeForContainer(String container) {
    switch (container.trim().toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'webm':
      case 'weba':
        return 'audio/webm';
      default:
        return 'audio/mpeg';
    }
  }

  /// Whether the server URL can plausibly be fetched by a Chromecast.
  ///
  /// Chromecasts resolve DNS via Google servers and require HTTPS with a
  /// valid certificate plus a LAN-routable host. Plain `http://`,
  /// `localhost`, and `.local`-style hosts fail on the receiver even though
  /// the phone itself can play them.
  static bool isServerReachableByCast(Uri serverUrl) {
    if (serverUrl.scheme != 'https') return false;
    final host = serverUrl.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host.startsWith('127.') ||
        host == '[::1]') {
      return false;
    }
    return true;
  }

  /// User-visible reason when the server cannot be used for Cast, if any.
  static String? serverBlockerMessage(Uri serverUrl) {
    if (serverUrl.scheme != 'https') {
      return 'This Jellyfin server uses plain HTTP and cannot be reached '
          'by Chromecast. Use an HTTPS address to cast.';
    }
    final host = serverUrl.host.toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host.startsWith('127.') ||
        host == '[::1]') {
      return 'This Jellyfin server address is only reachable from this '
          'phone. Chromecast needs a server address reachable on your '
          'Wi-Fi network.';
    }
    return null;
  }

  Uri streamUriForCast(
    JellyfinSession session,
    String itemId, {
    bool small = false,
  }) => _client.streamUri(session, itemId, small: small);

  Uri artworkUriForCast(JellyfinSession session, String itemId) =>
      _client.imageUri(session, itemId);

  /// Builds the handoff payload for [track] at [position].
  ///
  /// When [small] is true the AAC/m4a transcode profile is used (Cast
  /// fallback for exotic containers, mirroring `downloadUri(small: true)`).
  CastTrackPayload buildPayload(
    JellyfinSession session,
    Track track, {
    required Duration position,
    String? playlistItemId,
    bool small = false,
  }) {
    final duration = Duration(microseconds: track.durationTicks ~/ 10);
    final safePosition = position.isNegative
        ? Duration.zero
        : (duration == Duration.zero || position <= duration
              ? position
              : duration);
    return CastTrackPayload(
      contentId: track.id,
      contentUrl: _client.streamUri(session, track.id, small: small),
      contentType: small
          ? 'audio/mp4'
          : contentTypeForContainer(track.container),
      title: track.name,
      artist: track.artist,
      album: track.album,
      artworkUrl: _client.imageUri(session, track.albumId ?? track.id),
      duration: duration,
      startPosition: safePosition,
      itemId: track.id,
      playlistItemId: playlistItemId,
    );
  }
}
