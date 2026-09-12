### Verification

* Verify changes with `flutter analyze`, `flutter test`, and `dart format --output=none --set-exit-if-changed lib test`.
* For web-touching changes, also run `flutter test --platform chrome test/session_store_test.dart`.

### Database

* After a table change and a `schemaVersion` bump, run `dart run drift_dev schema dump lib/storage/database.dart drift_schemas/`, then `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`; never hand-edit generated files.
* Expose drift `watch*()` streams as providers in `lib/app/providers.dart`; never call `database.watch*()` inside a widget `build`.

### Networking

* Bound requests with `Future.timeout` over the whole call (`get`/`post`/`delete`); never wrap response bodies with `Stream.timeout` — it deadlocks widget tests.

### Builds

* Build web only through `bash scripts/build-web.sh`; do not call `flutter build web` directly.

### Security

* Route server- and user-supplied path segments through `safePathSegment`; add new secret shapes only to `redactSecrets`.
