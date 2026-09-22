### Delivery preconditions

* After checkout: run `mise trust` once, then invoke the toolchain only via `mise exec --`.
* Before the first commit/push: ensure worktree-scoped git identity (`git config --worktree user.name`/`user.email`) is set and run `gh auth setup-git` once so `git push` uses the authenticated helper. If a push fails with `could not read Username`, re-run `setup-git` before trying other fixes.
* When integrating work from a branch based on an older `main`: check `git merge-base --is-ancestor <commit> origin/main`. If not an ancestor and `main` moved ahead, cherry-pick/rebase onto current `origin/main` and confirm the final diff touches only the fix's files.
* Verification honesty: if the full suite fails on files you did not touch (pre-existing `main` breakage), verify the touched boundary (`mise exec -- flutter analyze <files>`, focused tests, format) and name the pre-existing failure in the handoff. Never move to `in_review` with verification silently skipped because the toolchain was unavailable — report `toolchain blocked, unverified` instead.

### Verification

* Verify changes with `mise exec -- flutter analyze`, `mise exec -- flutter test`, and `mise exec -- dart format --output=none --set-exit-if-changed lib test`.
* For web-touching changes, also run `mise exec -- flutter test --platform chrome test/session_store_test.dart`.

### Database

* After a table change and a `schemaVersion` bump, run `mise exec -- dart run drift_dev schema dump lib/storage/database.dart drift_schemas/`, then `mise exec -- dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`; never hand-edit generated files.
* Expose drift `watch*()` streams as providers in `lib/app/providers.dart`; never call `database.watch*()` inside a widget `build`.

### Networking

* Bound requests with `Future.timeout` over the whole call (`get`/`post`/`delete`); never wrap response bodies with `Stream.timeout` — it deadlocks widget tests.

### Builds

* Build web only through `bash scripts/build-web.sh`; do not call `mise exec -- flutter build web` directly.
* Release through `./scripts/release.sh x.y.z`; it owns the `pubspec.yaml` version — do not bump it by hand.

### Security

* Route server- and user-supplied path segments through `safePathSegment`; add new secret shapes only to `redactSecrets`.

### Skills

* Store project skills in `.agents/skills/<id>/SKILL.md` with `name` and `description` frontmatter.
