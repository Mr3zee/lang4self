# Communication

- Keep updates concise and direct; the user has ADHD.

# Git

- Never create merge commits. Use rebase or fast-forward.

# Evolution rules

- Compose production dependencies in `Lang4SelfApp`; pass them into state and services through protocols. Do not add global/shared service singletons.
- Keep coordinator initializers explicit: no production fallbacks to concrete stores, settings, process arguments, clocks, or external adapters.
- Keep views free of SQLite, process, network, and filesystem work. Views send intent to `AppState`; adapters implement side effects.
- Put workflows used by more than one executable in `Lang4SelfCore` instead of copying them into app/CLI/tool targets.
- Do not append unrelated responsibilities to `AppState`, `LocalStore`, or `LMStudioService`. Add a focused type and expose only the capability its caller needs.
- Treat stored data as an API. Every SQLite change must increment `latestSchemaVersion`, run as an ordered transaction, preserve existing user data, and include migration tests. Never rewrite an already-released migration.
- Keep schema setup and migrations in `LocalStoreSchema`; check every SQLite prepare/step/commit result.
- Make workflows that perform multiple related writes atomic and add a rollback regression test.
- Inject clocks and calendars when behavior depends on dates. Cover a non-UTC time zone and day boundaries in tests.
- Inject settings, stores, runtime flags, and external adapters. Tests must not require a user's database, preferences, LM Studio installation, or network.
- Keep initializers limited to validation and dependency wiring. Start asynchronous work from an explicit lifecycle method or view task.
- Own cancellable UI work with a stored task, cancel superseded work, and reject stale results before mutating state.
- Add the smallest regression test at the lowest viable layer. Run `swift test`; for UI behavior, follow the macOS UI-test workflow below.

# macOS UI tests

- Tests live in `Tests/Lang4SelfUITests/Lang4SelfUITests.swift`.
- Run only the focused test(s) relevant to the change by default, using `-only-testing:Lang4SelfUITests/Lang4SelfUITests/testName`.
- Do not run the full UI-test target unless the user explicitly asks for it; the full suite is very slow.
- Always pass `-skipPackagePluginValidation`; otherwise Xcode blocks the MLX `CudaBuild` package plugin.
- Use Xcode's default Derived Data. Never use `-derivedDataPath .derived`: this Desktop-hosted repository causes repeated macOS permission prompts.
- Add stable accessibility identifiers and deterministic `--ui-testing` fixtures for new interactions.
- Ignore locked-iPhone `notification_proxy` warnings; they are unrelated to macOS tests.
- When the user explicitly asks for the full UI suite, run it with:

```sh
xcodebuild -quiet -project Lang4Self.xcodeproj -scheme Lang4Self \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation \
  -only-testing:Lang4SelfUITests test
```
