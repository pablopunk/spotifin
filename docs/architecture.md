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

## Checks still required

The framework choice is settled; playback and storage choices still need checks
for web offline use, iOS background playback, AirPlay, and CarPlay.
No playback, storage, state management, or sync package has been selected yet.

## References

- [Product requirements](PRD.md)
- [Player research](player-research.md)
