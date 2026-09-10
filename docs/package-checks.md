# Package and API checks

Checked: 2026-09-10.

This is a documentation and source review, not a device test or a compatible
dependency lockfile; versions below were the latest reported by pub.dev when
checked, and must be resolved together before implementation.

## Planned dependencies

| Package | Version checked | Use and limits |
| --- | --- | --- |
| [just_audio](https://pub.dev/packages/just_audio) | 0.10.6 | Audio engine for iOS/web first; Windows/Linux need extra implementations; built-in experimental download cache is not supported on web |
| [audio_service](https://pub.dev/packages/audio_service) | 0.18.19 | Shared audio handler, background playback and system media controls; not a complete CarPlay browse interface |
| [audio_session](https://pub.dev/packages/audio_session) | 0.2.4 | Audio focus, interruption and Apple session configuration |
| [flutter_carplay](https://pub.dev/packages/flutter_carplay) | 1.6.5 | Candidate for CarPlay templates and cold launch; requires native setup and audio entitlement |
| [drift](https://pub.dev/packages/drift) | 2.35.0 | Typed SQLite queries, transactions, migrations and streams |
| [drift_flutter](https://pub.dev/packages/drift_flutter) | 0.3.1 | Native and web database setup; web needs Wasm and worker assets |
| [background_downloader](https://pub.dev/packages/background_downloader) | 9.6.1 | Native background transfers; supports desktop but not web; OS can stop tasks |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | 11.1.0 | Native token storage; browser storage has different guarantees |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | 3.4.3 | Shared service setup and screen state |
| [go_router](https://pub.dev/packages/go_router) | 18.0.1 | Navigation and browser routes |
| [http](https://pub.dev/packages/http) | 1.6.0 | Small typed Jellyfin client and lyric requests |

Choose a compatible stable set rather than requiring every latest version.
Check package licenses and minimum SDK targets when adding dependencies.

## Important findings

- The [just_audio source documentation](https://github.com/ryanheise/just_audio/tree/minor/just_audio)
  confirms URL playback on all targets, but web cannot attach arbitrary audio
  request headers; check Jellyfin's authenticated media URL flow.
- The same documentation lists experimental caching as native-only; web audio
  persistence needs the planned browser adapter.
- [Drift web documentation](https://drift.simonbinder.eu/platforms/web/) describes
  automatic selection of OPFS or IndexedDB implementations, with an in-memory
  fallback; inspect the chosen mode rather than assuming persistence.
- [background_downloader documentation](https://github.com/781flyingdutchman/background_downloader)
  describes native transfers and restart reconciliation, but force-closing an
  app can stop transfers.
- [flutter_carplay documentation](https://pub.dev/packages/flutter_carplay)
  lists native list, tab and Now Playing templates and background launch support;
  test it with the audio handler rather than treating its feature list as proof.
- AirPlay route selection needs Apple integration and real receiver checks;
  it is not established by the audio package's platform table.
- [Jellyfin's stable OpenAPI](https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json)
  reported version 12.0.0: playlist add, remove and move endpoints exist, removals
  use entry IDs, and MarkPlayedItem accepts `datePlayed`.
- User-data writes expose `PlayCount` and `LastPlayedDate`; field availability
  alone does not establish a safe concurrent offline replay protocol.
- [Jellyfin MusicManager source](https://github.com/jellyfin/jellyfin/blob/master/Emby.Server.Implementations/Library/MusicManager.cs)
  selects random genre-filtered audio for InstantMix, up to 200 items; it does
  not implement Spotifin's artist expansion rule (master inspected, not a pinned
  server release).
- [LRCLIB](https://lrclib.net/docs) remains a candidate based on Feishin's source;
  the documentation fetch returned no usable text, so browser access and exact
  matching behavior are still unverified.
- [Codemagic](https://docs.codemagic.io/getting-started/building-a-flutter-app/)
  documents Flutter cloud builds, signing, TestFlight uploads and store submission.

## Unproven release requirements

Web offline startup and seeking, iOS background playback, normalization, CarPlay,
AirPlay, and interrupted offline sync still require executable checks described
in [architecture](architecture.md).
