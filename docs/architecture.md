# Spotifin architecture

Status: implementation plan; package choices checked against documentation,
but not yet tested together on devices.

Updated: 2026-09-10.

## Structure

Use one Flutter app in one repository, with feature folders and small shared
services; no extra Spotifin backend is required.

```text
lib/
  app/                 startup, routes, theme, service setup
  features/
    home/              recent music and mixes
    library/           browse, search, albums, artists
    playlists/         playlist screens and edits
    player/            queue and now-playing screens
    downloads/         download screens
    settings/          account and device settings
  services/
    jellyfin/          API requests and response models
    catalog/           refresh and local queries
    playback/          shared queue and audio handler
    downloads/         download ownership and task handling
    sync/              pending writes and listening reports
    mixes/             tag groups and daily selection
    lyrics/            Jellyfin lookup and external fallback
  storage/             Drift tables, queries, migrations
  platform/            browser and native system adapters
web/                   manifest, service worker, browser assets
ios/                   Apple setup and small native integrations
test/                  shared rules and integration checks
```

Screens read service state and send commands; they do not call Jellyfin or the
audio engine directly.
Use Riverpod for service setup and screen state, Drift streams for stored data,
and go_router for navigation and web URLs.
Do not keep a second copy of the catalog in screen state.

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

Use Drift with SQLite on native platforms and its Wasm database on web.
Keep audio files outside the database.

Refresh on sign-in, app foreground, reconnection, and explicit refresh.
Allow only one refresh per account at a time; use a five-minute foreground
refresh interval as an initial default.
Fetch items in pages of 500 and make the first page usable before the full
refresh ends.
Mark the refresh complete before removing local items absent from its results.
A failed page must not cause local deletions.
Refresh favorites and playlist contents as well as catalog metadata.

Use indexed local queries for search and virtual lists for large results.
Fetch artwork on demand; keep artwork for downloaded music.

Store these small, focused tables:

| Table group | Purpose |
| --- | --- |
| Items, artists, item artists, labels | Catalog text, relationships, genres and tags |
| User data | Jellyfin favorites, play counts, last played date |
| Playlists and entries | Server entry IDs, song IDs, order, pending local entries |
| Pending writes | Durable offline operations and their attempt state |
| Downloads and owners | Files, quality, status, and albums/playlists that need them |
| Queue and settings | Current device playback and preferences |
| Mix snapshots and lyrics | Daily selections and cached lyric text |

Scope stored data to the Jellyfin server ID and user ID.
Version the database and test migrations before releases.

## Jellyfin connection

Use `package:http` behind one small Jellyfin client, with typed models for the
endpoints the app uses; do not build a general server SDK.
Keep the server URL base path intact for reverse-proxy installations.
Use Jellyfin sign-in and store the returned token, not the password.
Use `flutter_secure_storage` for native tokens and browser-local storage for
web tokens; browser storage is not equivalent to the iOS Keychain.
Exclude tokens and authenticated URLs from logs and app-shell caches.
Stop playback and clear account-local data on explicit sign-out.

Use authenticated API requests to determine server reachability; network status
alone does not prove that Jellyfin is available.
Pause sync on expired authentication and let the user sign in again.
Keep downloads usable during a temporary connection failure.

Select and pin the minimum Jellyfin release during the first integration check.
The moving stable OpenAPI document checked on this date reports version 12.0.0;
it is not proof that all endpoints exist on older installations.

## Offline writes

Save each edit and its pending operation in one local database transaction.
Show the edit immediately, then send pending operations in order when connected.
One worker sends writes for the account; a browser lock prevents two tabs from
running that worker at once.
Coalesce repeated favorite changes into the final requested state.
The latest pending local favorite state wins when it is sent to Jellyfin.

Before changing a playlist, read its current entries:

- Keep server order and append local additions in their local order.
- Keep additions made by other clients.
- Remove only the specific server entry the user removed, using its entry ID.
- Treat an already absent entry as a completed removal.
- Preserve existing duplicate songs; track occurrences by entry ID.
- Use a temporary local ID for an offline-created playlist, then map it to its
  server ID after creation.
- Keep playlist reordering online-only initially; queue reordering is local.

Persist an attempt before sending a write.
After a timeout, re-read server state before retrying a non-idempotent operation
such as playlist creation or adding entries.
Use the saved pre-write entries and expected changes to reconcile the result.
If the result remains ambiguous, keep the operation pending with a retry action
rather than adding songs or playlists repeatedly.
Jellyfin does not provide a proven exactly-once merge protocol here.
Do not claim perfect sync under simultaneous writes from every client.

## Offline playlist deletion

If a playlist is deleted in Jellyfin while this device has pending edits to it,
the server deletion takes priority.
Discard those pending edits and remove the playlist from the local catalog.
Do not create a recovered playlist.
Only a confirmed deletion triggers this rule; connection failures do not.

## Playback restoration

Save the device queue, current track, and playback position locally.
Restore them after restart, with playback paused until the user presses Play.

## Playback

Use `just_audio` for audio, `audio_service` for background and system controls,
and `audio_session` for calls, audio focus, and route changes.
One shared audio handler owns playback; phone screens, CarPlay, and system
controls send commands to that handler.
The engine reports actual progress and errors back to shared state.

Playing an album or playlist replaces the queue.
Add to queue appends to the end; users can reorder or remove queued entries.
Use local queue entry IDs so the same song can appear more than once.
Repeat is off by default; stop and mark playback paused when the queue ends.
Save position periodically and on pause or track change, not every animation frame.
Resolve each source just before it is needed and prefer complete downloads.
Release old browser Blob URLs when their audio source is no longer needed.

### Quality and volume

Use PlaybackInfo and a device profile to choose playable Jellyfin sources.
Full quality prefers the original file; try a supported lossless conversion
when the original cannot play.
If only lossy conversion is available, identify it in playback details rather
than calling it original quality.
Small file initially targets AAC at 128 kbps in a seekable supported container;
confirm the server can produce that form as a complete download.
Use a supported MP3 fallback if required by the tested browser/device profile.
Store the actual format and quality with each download.

Normalization is on by default: use album gain for album playback and track gain
otherwise, where Jellyfin supplies it.
Do not scan audio or add a server plugin to calculate missing gain.
Verify gain application on Safari and iOS: a package volume method alone does not
prove equal normalization behavior on all platforms.

### Apple features

Use `flutter_carplay` as the first CarPlay integration candidate for native list,
tab, and Now Playing templates.
Show library shortcuts, playlists, and downloads through the same catalog service.
Start shared services without requiring the phone screen to be open.
Request the CarPlay audio entitlement for distribution and test cold launch.

Use the Apple playback audio session and an `AVRoutePickerView` integration for
AirPlay; a small Swift bridge is acceptable if no suitable plugin is needed.
Check authenticated streams and local downloads on a real AirPlay receiver.
Neither CarPlay nor AirPlay should create a second queue or audio player.

## Downloads

Use `background_downloader` for native file transfers and a browser adapter for
web transfers; this package does not implement web downloads.
Start with two concurrent audio downloads to limit server load.
Download to temporary storage, validate completion, then mark the file ready.
Use the correct extension and MIME type for the actual encoded audio.
Reconcile stored tasks and files after restart.

Track ownership rather than downloading a song once per playlist.
Removing one download owner deletes the file only when no owner needs it and
the player is not using it.
Refresh downloaded playlist membership while the app can sync; the operating
system does not guarantee arbitrary background catalog refresh.
Keep downloaded mix membership fixed until Update is selected.
Save available artwork and lyrics with downloads, but do not fail audio downloads
because optional artwork or lyrics are missing.

On native systems, use app-private files excluded from cloud backup.
On web, store complete audio responses in Cache Storage under account-scoped,
same-origin synthetic keys without tokens.
Read a stored response as a Blob for local playback, with seeking tested on Safari.
Do not store large audio bytes in Drift rows.
If this Blob approach is too costly for large tracks, use a service-worker route
with byte-range responses behind the same adapter.

Request persistent browser storage where supported and inspect storage estimates.
A storage quota error leaves the track incomplete; never silently delete an
explicit download to make room.
Check that files still exist after restart: browsers may evict local storage.
Web download tasks resume when the app is open; background completion after a
tab closes is not promised.

## Listening data

Send Jellyfin playback start, progress, and stop reports while online.
Keep offline listens locally with a stable event ID and original timestamp.
The current API exposes `datePlayed` on MarkPlayedItem and user-data write fields;
this corrects the older issue report that timestamps could not be supplied.
Verify how the chosen server version increments counts before enabling replay.
Replay confirmed unsent listens oldest first, avoiding changes that move the
server's last-played date backwards.
Do not overwrite server play counts with a stale local total.
For an ambiguous timeout, retain the event for reconciliation rather than blindly
incrementing the count again.
Exact event-history sync across clients is not a Jellyfin capability established
by this review.

## Mixes and lyrics

Generate mixes from the local catalog; this is one necessary custom feature.
The inspected Jellyfin InstantMix source filters songs by genre and chooses a
random result; it does not expand a tag group to all songs by selected artists.

Use song Tags and Genres as labels, preserving their original values.
Normalize case and whitespace and use a small explicit alias/group map for
related labels; do not infer labels for untagged libraries.
Select artists from labeled tracks, then allow all their songs into the pool.
Start with 50 unique tracks per mix, balanced between more-played and less-played
halves of that pool, rotating artists where the pool permits.
Keep the grouping map and selection function small and independently testable.
Build a daily snapshot on the first app use that day; no scheduled backend job.
The active queue and downloaded snapshots remain fixed.
Save as playlist writes the snapshot to Jellyfin.

Use Jellyfin lyrics first and LRCLIB as the first external provider candidate.
Try a metadata match using title, artist, album, and duration before a broader
search; show no lyrics rather than an uncertain recording match.
Cache plain or timed lyrics locally and retry missing results after a delay.
Do not add server lyric writes for v1.
LRCLIB browser access and matching still require an integration check.

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

Build Flutter in CI with a pinned stable SDK and publish `build/web` to Vercel.
Use an SPA fallback for app routes without rewriting service workers, Wasm, or
other asset requests to HTML.
Serve the manifest, app entry point, and service worker with update-friendly
cache headers; cache versioned assets for longer.
Cache the full app shell, including Drift's worker and Wasm files, for offline
startup after the first successful online load.
Activate app updates between listening sessions rather than reloading playback.
Confirm the database storage mode selected by Drift persists across browser restarts.

## Builds and publishing

Use Codemagic as the default proposed automation service for native builds;
the user requested automatic publishing but did not explicitly select a provider.
Build and test pull requests; send main-branch iOS builds to TestFlight and tagged
releases for App Store review.
Apple review still controls public availability.
Keep signing keys and store credentials in CI secrets.
Use the same pinned Flutter SDK locally and in CI and commit the app lockfile.
Vercel serves the web build; it does not need to run a Flutter server.

## Checks still required

Implement the checks below as the first small vertical slice, before full screens:

1. Sign in to a real Jellyfin server; pin its supported API version and record
   actual stream formats, range support, and browser access requirements.
2. Stream and download one track on web; close and reopen offline, then seek;
   verify the stored catalog and app shell survive restart.
3. Play a stream and download on iPhone with the screen locked; test headset
   controls, a call interruption, AirPlay, and CarPlay cold launch.
4. Check normalization with known gain metadata on web and iOS.
5. Edit a playlist offline, change it through Jellyfin, then reconnect; check
   additions, removals, deletion, duplicate entries, and interrupted writes.
6. Replay offline listens against the chosen server version and check timestamps
   and counts, including a timeout after server acceptance.
7. Load a 10,000-track catalog; measure time to first usable page, search response,
   memory use, and scrolling in release/profile builds.

Start browser checks with current Safari, Chrome, Firefox, and Edge, including
iPhone Safari; publish supported minimum versions only after those checks.
Set the iOS deployment target from the chosen package versions and device tests.
Windows and Linux later need an extra `just_audio` backend and separate system
media-control checks; Flutter support alone does not supply those integrations.

Test shared queue, sync, ownership, mix, and migration rules with unit tests.
Use integration tests for API and storage boundaries and manual checks for
visual quality, touch, CarPlay, AirPlay, and system playback behavior.
Ask the user to perform device and visual checks; no apps were run during this
documentation task.

## References

- [Product requirements](PRD.md)
- [Player research](player-research.md)
- [Package checks](package-checks.md)
