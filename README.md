# Lang4Self

A keyboard-first, fully local German-learning app for macOS 14+.

## Run it

1. Open `Lang4Self.xcodeproj` in Xcode.
2. Select the **Lang4Self** scheme and **My Mac**.
3. Press **⌘R**.
4. In **Settings**, request the `DE → EN` and/or `DE → RU` UTF-8 files from dict.cc, then import each downloaded ZIP or text file.
5. Optionally download Lector's [German SQLite dictionary](https://lector.dev/free/german-dictionary/) and import it in **Settings** to add offline Wiktionary explanations.
6. For sentence generation, install a text-generation model and the `lms` CLI from LM Studio. Choose the model and generation parameters in **Settings**. Lang4Self starts the localhost server, loads the model on first use, and offloads its model instance when the app quits.

The app includes a tiny original starter list. The complete dict.cc file stays on your Mac and is never committed or redistributed.

## Main controls

| Keys | Action |
|---|---|
| ⌘1 … ⌘6 | Dictionary, Speak, Review, My words, Sentences, Settings |
| ⌘, | Open Settings |
| ⌘F | Focus Dictionary or My words search; open Dictionary elsewhere |
| ⌘? | Show the complete keyboard shortcut reference |
| Tab / ⇧Tab | Move focus forward or backward |
| ↑ / ↓ | Navigate dictionary results, saved cards, and sentences |
| ← / → | Navigate words in the sentence inspector |
| Return | Enter results, edit a card, inspect a sentence, confirm speech, or accept a dialog |
| ⌘Return | Add the selected dictionary entry |
| ⌘⇧N | Create a list in My words |
| Hold Space | Record speech; release to look it up |
| Space | Reveal a review or activate a focused control |
| 1 … 4 | Rate a revealed review: Again, Hard, Good, Easy |
| Delete | Remove the selected saved card or sentence |
| Esc | Clear focused search, leave sentence inspection, or close a dialog |

## Local architecture

- SwiftUI macOS application
- Apple Speech with `requiresOnDeviceRecognition = true`
- SQLite + FTS5 for fast lookup across 1M+ entries
- Streaming tab-delimited import, so the whole source file is never loaded into memory
- Durable named word lists, personal cards, and review log
- Local LM Studio sentence generation from a selected word list, with explicit model loading and offloading
- A separate saved-sentences library with keyboard word inspection
- SM-2-style intervals with Again / Hard / Good / Easy
- Rule-based German morphology plus explicit common irregular forms
- Shared `Lang4SelfCore`, ready for later iOS and server targets

Run the core test suite with:

```sh
swift test
```

Run the standard architecture/build check with:

```sh
./scripts/check.sh
```

Run the macOS UI test suite with the **Lang4Self** scheme in Xcode, or with:

```sh
xcodebuild -quiet -project Lang4Self.xcodeproj -scheme Lang4Self \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:Lang4SelfUITests test
```

Build the actual app bundle from Terminal with:

```sh
./scripts/build-macos.sh
```

Build an optimized release app bundle with:

```sh
./scripts/build-release.sh
```

Stop, rebuild, and relaunch the development app with:

```sh
./scripts/reload-macos.sh
```

Build and install the release app on the Desktop and the CLI in `~/.local/bin`:

```sh
./scripts/release.sh
```

`./scripts/install.sh` remains an alias for the same command.

CLI examples:

```sh
lang4self                 # open the app
lang4self Haus            # search the local dictionary
lang4self stats
lang4self import dict.zip
lang4self import-explanations dictionary-de.db
```

## dict.cc licensing

dict.cc states that its translation data is **not open-source data**. Personal use is allowed, but each user must accept its terms and download their own copy. Software using it must be GPL-compatible, and the data must not be bundled or republished. Lang4Self therefore links to the official request page and only imports the user's local file.

Code in this repository is licensed under GPL-2.0-or-later. dict.cc data is governed separately by the dict.cc terms.

Imported explanations are derived from Wiktionary through kaikki.org and Lector and are licensed under CC BY-SA 4.0. They remain local and are not bundled with this repository.
