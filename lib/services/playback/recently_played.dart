import '../../storage/database.dart';

/// Merges Jellyfin Recently Played data with the transient session overlay.
///
/// [serverTracks] is Jellyfin's Recently Played truth (from
/// `fetchRecentlyPlayed`, or its cached form `watchRecentlyPlayed`), already
/// ordered most-recent-first. [sessionTracks] holds tracks played in this app
/// session since the last sync/server confirmation, also most-recent-first.
///
/// Presentation-only transformations (the only allowed deviations from the
/// server order):
/// 1. Session tracks come first, so a just-finished track appears instantly
///    without waiting for the server to record it and for the next sync to
///    cache it. Once the server confirms the play, the track is naturally
///    deduped into its server position on a later merge.
/// 2. Entries are deduped by track id (session copy wins).
/// 3. The merged list is capped at [limit] (Jellyfin default page is 100).
///
/// Offline/error behavior is explicit: when the server list is unavailable,
/// callers pass an empty [serverTracks] and the session overlay alone is
/// shown; when both are empty the UI shows the empty state. Nothing here is
/// persisted: Jellyfin remains the only durable history store.
List<Track> mergeRecentlyPlayed({
  required List<Track> serverTracks,
  required List<Track> sessionTracks,
  int limit = 100,
}) {
  final seen = <String>{};
  final merged = <Track>[];
  for (final track in [...sessionTracks, ...serverTracks]) {
    if (!seen.add(track.id)) continue;
    merged.add(track);
    if (merged.length >= limit) break;
  }
  return merged;
}
