# Spotifin

Spotifin is a free, open-source, Spotify-style music player that connects
directly to an existing Jellyfin server.

## Run

Install the pinned toolchain with [mise](https://mise.jdx.dev/), then run:

```sh
mise install
mise exec -- flutter pub get
mise exec -- dart run build_runner build
mise exec -- flutter run -d chrome
```

For development auto-login, copy `.env.example` to `.env`, enter your Jellyfin
details, and run:

```sh
mise run dev
```

Flutter listens on all interfaces at port 8080 but opens Chrome at the secure
`localhost` origin. The ignored `.env` credentials are compiled into this
development build, so use HTTPS for remote access and do not expose it to
untrusted networks.

For an iPhone, enable Developer Mode, pair it with Xcode, then select it from
`mise exec -- flutter devices` and use `mise exec -- flutter run -d <device-id>`.

## Checks

```sh
mise exec -- flutter analyze
mise exec -- flutter test
mise exec -- flutter build web --release
mise exec -- flutter build ios --release --no-codesign
```

The iOS build needs the matching iOS platform component in Xcode and the
CarPlay audio entitlement before distribution.

## Deploy

- Vercel uses `vercel.json` and `scripts/build-web.sh` for the static web app.
- Codemagic uses `codemagic.yaml` for signed TestFlight builds after its App
  Store Connect integration and signing profile are configured.

Product and engineering decisions are in [`docs/`](docs/).
