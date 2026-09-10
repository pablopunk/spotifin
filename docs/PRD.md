# Spotifin product requirements

Status: draft for review.

## Product

Spotifin is a free, open-source music player for existing Jellyfin users.
It provides a simple, Spotify-like experience for their own music collection.

Web and iOS are the first release targets. Android, macOS, Windows, and Linux
are later targets. Core behavior and design must remain consistent across them.
The interface must work with touch, mouse, and keyboard.

Use a familiar Spotify-style layout and motion, with original colors and design.
Animations must be smooth and must respect reduced-motion settings.

## Backend rules

- Connect directly to one existing Jellyfin server and account at a time.
- Require no server plugins or extra Spotifin service for core music features.
- Use Jellyfin features and data wherever they meet the requirements.
- Keep playlists, favorites, and listening data in Jellyfin where its API permits.
- Combine all music libraries available to the account into one catalog.
- Support music only in v1.
- Target collections of up to 10,000 tracks.
- Use local storage for downloads, cached data, the device queue, and pending offline changes.
- An external lyrics service is allowed when Jellyfin has no lyrics.

Custom behavior must fill a proven gap rather than duplicate a Jellyfin feature.

## Browse and search

- Browse and search songs, albums, artists, and playlists.
- Show the full available music catalog.
- Use Jellyfin favorites for songs, albums, and artists.
- Home includes recently played, recently added, favorites, and generated mixes.
- Provide a Downloaded filter for music available offline.
- Missing artwork or metadata must not prevent browsing or playback.

## Playback and queue

- Play music on the current device.
- Playing an album replaces the queue with its tracks in album order.
- Playing a playlist replaces the queue with its tracks in playlist order.
- Users can add songs to the queue.
- Playback stops when the queue ends; do not append recommended songs automatically.
- Provide play, pause, seek, previous, next, shuffle, and repeat controls.
- Support background playback and system media controls on iOS.
- Include Apple CarPlay and AirPlay in v1.
- Prefer a complete local download over streaming, even when streaming quality is higher.
- Include volume normalization, on by default, using Jellyfin data when available.
- Do not block playback when normalization data is absent.

Restore the saved queue and playback position after restart, but wait for the
user to press Play.
The architecture default is to append added songs to the queue and allow local
queue reordering and removal.

## Audio quality

- Keep quality settings simple: Full quality and Small file.
- Allow separate choices for streaming and downloads.
- Use Jellyfin direct playback and transcoding support.
- Do not expose bitrate or codec controls in the normal settings interface.
- No Wi-Fi-only download rule or mobile-data setting is required for v1.

The technical design must define the formats behind each quality choice and
handle devices that cannot play the original format.
It must not label lossy conversion as unchanged original quality.

## Downloads and offline use

- Both web and iOS support downloads for playback inside Spotifin.
- Downloaded music is not a file-export feature.
- Downloaded playlists follow additions and removals when the app can sync online.
- Keep a downloaded mix unchanged until the user chooses to update it.
- Offline users can change playlists and favorites.
- Sync pending changes when the server connection returns.
- Merge concurrent playlist changes while keeping added songs.
- Keep available artwork and lyrics with downloaded music.
- Show pending, downloading, complete, and failed states.
- A failed or partial download must not appear ready for offline playback.
- A song still needed by another downloaded album or playlist must remain available.

Use the simple conflict and retry rules in [architecture](architecture.md): keep
server playlist order, append offline additions, and let a confirmed server
playlist deletion take priority over pending edits.
Verify interrupted writes and duplicate entries before release.
Browser storage limits and eviction must be tested; permanent browser storage
has not been established as a guarantee.

## Mixes

The agreed selection process is:

1. Read tags from songs in the Jellyfin library.
2. Group related tags.
3. Find artists represented in each group.
4. Select from all library songs by those artists, including songs without those tags.
5. Balance frequently played songs with less-played songs from those artists.

- Refresh Home mixes once a day.
- Do not change a mix already in the playback queue.
- Save as playlist creates a fixed Jellyfin playlist from the current mix.
- Later changes to the Home mix do not change that saved playlist.
- Do not add per-song controls to exclude songs from future mixes in v1.
- Songs without tags can enter a mix through their selected artist.
- Do not invent tag groups for libraries with no usable tag data.

Check Jellyfin's mix endpoints before building custom selection code.
Use them only if they meet the agreed behavior.
Initial label grouping, mix size, and artist balance defaults are documented in
[architecture](architecture.md) and must be checked with real library data.

## Lyrics

- Use Jellyfin lyrics first.
- Highlight the current line when timing data exists.
- Show plain text when lyrics have no timing data.
- Search an external source when Jellyfin lyrics are missing.
- Match the recording using available title, artist, album, and duration data.
- Missing lyrics or a failed lookup must not interrupt playback.

LRCLIB is a candidate based on Feishin's implementation.
It is the first provider candidate in the architecture; browser access and
matching still need checks.
Keep externally found lyrics locally in v1.

## Out of scope for v1

- Server setup or library administration.
- Multiple accounts or servers.
- Video, podcasts, and audiobooks.
- Spotify Connect-style control between Spotifin devices.
- Gapless playback and crossfade.
- Automatic continuation after the queue ends.
- Sleep timer.
- Music file export.
- Per-song mix exclusion controls.

AirPlay and CarPlay are included and are distinct from cross-device app control.

## Required technical checks

1. Compare Jellyfin InstantMix and related-item APIs with the specified mix rules.
2. Verify offline play-count and timestamp writes against the current Jellyfin API.
3. Define safe offline playlist and favorite sync, including repeated requests.
4. Prove web offline startup, playback, seeking, and storage recovery.
5. Prove iOS background playback, downloads, CarPlay, and AirPlay.
6. Verify quality choices and playback compatibility across first-release platforms.
7. Verify external lyrics lookup from both web and iOS.
8. Select the minimum Jellyfin version and supported browser versions.
9. Verify Flutter playback and storage packages through the playback and offline checks.

Flutter is selected for all platforms; see [architecture](architecture.md).

## Release checks

- A user can sign in and browse combined music libraries with 10,000 tracks.
- Playing an album or playlist replaces the queue and stops at its end.
- Added queue songs play before playback stops.
- A complete download plays without the server on both first-release platforms.
- A smaller local download is used even when full-quality streaming is selected.
- Playlist updates preserve songs required by other downloads.
- Offline edits reach Jellyfin after reconnection without losing concurrent additions.
- Saved mixes remain fixed while Home mixes refresh.
- Lyrics follow playback when timing data exists and remain usable offline when saved.
- CarPlay, AirPlay, background playback, and system controls work on iOS.
- Touch, mouse, keyboard, screen-reader access, and reduced motion receive manual checks.

Exact performance budgets and the supported device/browser test list remain open.

## References

- [Repository research](player-research.md)
- [Jellyfin stable API specification](https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json)
