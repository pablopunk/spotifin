# Jellyfin music player research

Research date: 2026-09-09.

This is a historical research note; the [PRD](PRD.md) and
[architecture](architecture.md) record later decisions, and
[package checks](package-checks.md) update the API findings, including offline
play timestamps.

## Goal

Use existing players to find useful design choices for Spotifin: a simple,
Spotify-like music app, with web and iOS first.

This review covers repository documents, selected source files, and issues.
The apps were not run, so visual quality and playback reliability were not tested.
Issue reports describe user experience; they do not prove current API limits.

## Repositories inspected

| Project | Platforms and approach | Source revision |
| --- | --- | --- |
| [Finamp](https://github.com/finamp-app/finamp) | Flutter; iOS and Android, with desktop work | `redesign`, `8d474f5` |
| [Feishin](https://github.com/jeffvli/feishin) | Electron desktop and a web build | `development`, `d90ca512854127575985a18f4cb9d7eb1e5afe2a` |
| [AmpFin](https://github.com/rasmuslos/AmpFin) | Native Apple app; Swift and AVFoundation | `main`, `7233c63f687a34edfd039689b7afbd365b7d6feb` |
| [Fintunes](https://github.com/leinelissen/jellyfin-audio-player) | React Native; iOS and Android | `main`, `13f25aca597bce0b04d0ed4e6292050cb680bae7` |

AmpFin's README states distribution restrictions in its license; it is a design
reference, not an assumed source of reusable code.

## Findings

### 1. Cross-platform UI does not remove platform-specific audio work

- Feishin offers separate MPV and browser playback backends.
- Fintunes uses React Native Track Player for the playback queue and native file storage for downloads.
- AmpFin uses AVFoundation playback and URLSession download callbacks.
- Finamp has a separate queue service and local listening log.

Recommendation: share product rules and data handling, but allow platform-specific
playback and download code; test web offline playback and iOS background playback
before selecting the final framework.

### 2. Existing mixes are useful references, but do not define Spotifin's mixes

- Finamp's `lib/services/audio_service_helper.dart` uses Jellyfin InstantMix and
  supports artist, album, and genre selections.
- Feishin's `src/renderer/api/jellyfin/jellyfin-controller.ts` tries similar songs,
  then falls back to InstantMix when needed.
- AmpFin's `AmpFinKit/Sources/AFPlayback/LocalAudioEndpoint/LocalAudioEndpoint+Queue.swift`
  fills an infinite queue with InstantMix results and filters recent history.

Spotifin's agreed rule remains: read song tags, group related tags, select artists
from those groups, then allow all library songs by those artists into the mix.
Home mixes refresh daily without changing the active queue.
Saving a mix creates a fixed Jellyfin playlist.
A downloaded mix keeps its songs until the user updates it.

Open product choice: whether music continues automatically after an album or
playlist ends.

### 3. Offline listening and offline edits are separate problems

- Finamp's `lib/services/offline_listen_helper.dart` records offline listens locally.
- Its [offline listening issue](https://github.com/finamp-app/finamp/issues/1064)
  discusses problems with server play counts and timestamps.
- Its [offline playlist request](https://github.com/finamp-app/finamp/issues/1065)
  and [offline favorites request](https://github.com/finamp-app/finamp/issues/933)
  show demand for edits without a connection.
- Feishin has an [offline playback request](https://github.com/jeffvli/feishin/issues/47);
  a web build alone is not evidence of complete offline support.

Spotifin already requires offline playlist and favorite edits, later sync, and
merging playlist changes while keeping additions.
Verify current Jellyfin write APIs before promising exact offline history replay.
Removal conflicts, reordered songs, and retry behavior still need a defined rule.

### 4. Downloads need one clear user model

- AmpFin documents automatic downloads for songs added to downloaded playlists.
- Fintunes' `src/components/DownloadManager.ts` limits concurrent downloads and
  attempts to recover file references after local state is lost.
- Finamp users request [preference for downloaded audio](https://github.com/finamp-app/finamp/issues/1745)
  and [access to downloaded music while online](https://github.com/finamp-app/finamp/issues/1721).

Recommendation: one library, a Downloaded filter, automatic use of downloaded
audio, clear incomplete-download status, and no required manual offline switch.
Artwork and available lyrics should accompany audio downloads.

Open product choice: play a smaller downloaded file while online, or stream full
quality when those quality settings differ.

### 5. External lyrics have a concrete reference

Feishin's `src/main/features/core/lyrics/lrclib.ts` queries LRCLIB with title,
artist, album, and duration, and prefers synced lyrics over plain text.
That code runs in its desktop main process; it does not establish browser support.

Spotifin already requires Jellyfin lyrics first, external lookup if missing,
synced line highlighting when available, and plain text otherwise.
LRCLIB is a candidate; verify its current API, browser access, and matching rules.

### 6. Familiar playback has choices beyond screen layout

AmpFin has an editable queue, playback history, and infinite playback.
Finamp documents volume normalization and has queue support for normalization gain.
Fintunes documents AirPlay and Chromecast.

Open product choices worth discussing:

- Automatic continuation after the selected music ends.
- Consistent song volume by default when Jellyfin has the required data.
- AirPlay and CarPlay scope, distinct from the excluded cross-device control.
- A saved collection of albums and artists versus treating the whole server as Your Library.

## Interview rules for the next step

- Ask one product question at a time, with a recommendation.
- Keep already agreed requirements closed unless research reveals a conflict.
- Research API and platform facts rather than asking the user to guess.
- Do not turn basic playback, search, or app navigation into approval questions.
