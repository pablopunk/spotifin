# Spotifin architecture

Status: architecture interview in progress.

## Framework

Use Flutter and Dart for web, iOS, Android, macOS, Windows, and Linux.
Web and iOS remain the first release targets.

Share as much screen code and app logic as possible across platforms.
Use plugins and small platform-specific modules where system features require
them, including playback, downloads, storage, AirPlay, and CarPlay.
CarPlay uses Apple's native screen templates connected to the shared app logic.

## Design

Use a custom Spotify-style design with consistent behavior across platforms.
The design does not need to copy native system controls exactly.
Superlist is an acceptable reference for the feel of a Flutter app.
Adapt layout and input behavior to each device.

## Local catalog

Keep a local copy of the full available music catalog's text data for fast
browsing and offline search.
Jellyfin remains the source of truth; refresh the local copy from the server.
Download audio only when the user requests it.
Catalog entries alone do not mean a song is available for offline playback.

The storage package and catalog refresh method remain to be selected.

## Web deployment

Host the first web release on Vercel as static Flutter build files.
Users open the public app URL and connect to their own Jellyfin server.
The browser sends music, artwork, and API requests directly to Jellyfin.
Vercel serves the app files and updates; it does not proxy Jellyfin traffic.
Use browser caching to reduce repeat requests for app files.

Add the manifest, service worker, and local storage needed for installable web
and offline use; a static Flutter build alone does not meet those requirements.
Check HTTPS, cross-origin access, and browser network restrictions when connecting
to a Jellyfin server.

## Checks still required

The framework choice is settled; playback and storage choices still need checks
for web offline use, iOS background playback, AirPlay, and CarPlay.
No playback, storage, state management, or sync package has been selected yet.

## References

- [Product requirements](PRD.md)
- [Player research](player-research.md)
