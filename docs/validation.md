# Implementation validation

Validated: 2026-09-10.

## Automated checks

- `flutter analyze`: no issues.
- `flutter test`: six tests pass for authentication responses, mix expansion,
  untagged music, durable favorite edits, and duplicate playlist additions.
- `flutter build web --release`: passes, including the Wasm compatibility check.
- `flutter build ios --release --no-codesign`: passes against Xcode 26.3 and
  the iOS 26.3.1 platform.
- `flutter build macos --release`: passes.
- Vercel JSON, web manifest JSON, Codemagic YAML, and GitHub Actions YAML parse.

## Live Jellyfin checks

Tested against Jellyfin 12.0.0 without a server plugin:

- Authentication and CORS preflight pass.
- The catalog loads in pages and cached songs appear immediately after restart.
- Search returns local results.
- Original audio streams with byte-range responses.
- Playback start, progress, pause, and stop reports reach Jellyfin.
- A full-quality browser download completes through Jellyfin's authenticated
  download endpoint.
- The downloaded song plays from a local Blob URL without a new Jellyfin audio
  request.
- Sign-out revokes the Jellyfin session and clears the local audio cache.
- Database migrations from schema 1 through schema 3 preserve the cached catalog.

The browser accessibility audit reports zero WCAG A/AA violations; Flutter's
canvas semantics leave color contrast as an incomplete automated check, so it
still needs visual review.

## Manual release checks

The following checks require the app owner's devices or external credentials:

- Sign and run on an iPhone; verify lock-screen controls, interruptions,
  background playback, a native download, and AirPlay on a real receiver.
- Request and configure Apple's CarPlay audio entitlement, then verify cold
  launch and playback in a vehicle or CarPlay simulator.
- Configure Codemagic's App Store Connect integration and signing profile, then
  confirm the first TestFlight upload.
- Connect Vercel to the repository and confirm an offline reload of the deployed
  origin after one successful online load.
