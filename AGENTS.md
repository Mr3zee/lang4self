# Communication

- Keep updates concise and direct; the user has ADHD.

# Git

- Never create merge commits. Use rebase or fast-forward.

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
