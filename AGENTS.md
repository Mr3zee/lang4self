# Communication

- Keep updates concise and direct; the user has ADHD.

# Git

- Never create merge commits. Use rebase or fast-forward.

# Evolution rules

- Compose production dependencies in `Lang4SelfApp`; pass them into state and services through protocols. Do not add global/shared service singletons.
- Keep views free of SQLite, process, network, and filesystem work. Views send intent to `AppState`; adapters implement side effects.
- Put workflows used by more than one executable in `Lang4SelfCore` instead of copying them into app/CLI/tool targets.
- Do not append unrelated responsibilities to `AppState`, `LocalStore`, or `LMStudioService`. Add a focused type and expose only the capability its caller needs.
- Treat stored data as an API. Every SQLite change must increment `latestSchemaVersion`, run as an ordered transaction, preserve existing user data, and include migration tests. Never rewrite an already-released migration.
- Inject time, settings, stores, and external adapters when behavior depends on them. Tests must not require a user's database, preferences, LM Studio installation, or network.
- Keep initializers limited to validation and dependency wiring. Start asynchronous work from an explicit lifecycle method or view task.
- Add the smallest regression test at the lowest viable layer. Run `swift test`; for UI behavior, follow the macOS UI-test workflow below.

# macOS UI tests

- Tests live in `Tests/Lang4SelfUITests/Lang4SelfUITests.swift`.
- Run one test first with `-only-testing:Lang4SelfUITests/Lang4SelfUITests/testName`, then run the full UI-test target.
- Use Xcode's default Derived Data. Never use `-derivedDataPath .derived`: this Desktop-hosted repository causes repeated macOS permission prompts.
- Add stable accessibility identifiers and deterministic `--ui-testing` fixtures for new interactions.
- Ignore locked-iPhone `notification_proxy` warnings; they are unrelated to macOS tests.
- Run all UI tests with:

```sh
xcodebuild -quiet -project Lang4Self.xcodeproj -scheme Lang4Self \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:Lang4SelfUITests test
```
