# Lang4Self

A keyboard-first, fully local German-learning app for macOS 14+.

## Run it

1. Open `Lang4Self.xcodeproj` in Xcode.
2. Select the **Lang4Self** scheme and **My Mac**.
3. Press **⌘R**.
4. In **Settings**, request the `DE → EN` UTF-8 file from dict.cc, then import the downloaded ZIP or text file.

The app includes a tiny original starter list. The complete dict.cc file stays on your Mac and is never committed or redistributed.

## Main controls

| Keys | Action |
|---|---|
| ⌘1 … ⌘5 | Dictionary, Speak, Review, My words, Settings |
| ⌘F | Focus dictionary search |
| Hold Space | Record speech; release to stop (Space reveals a review) |
| Return | Confirm a spoken word or phrase |
| 1 … 4 | Again, Hard, Good, Easy |
| ↑ / ↓ | Navigate results and cards |
| Delete | Remove the selected card from its list |

## Local architecture

- SwiftUI macOS application
- Apple Speech with `requiresOnDeviceRecognition = true`
- SQLite + FTS5 for fast lookup across 1M+ entries
- Streaming tab-delimited import, so the whole source file is never loaded into memory
- Durable named word lists, personal cards, and review log
- SM-2-style intervals with Again / Hard / Good / Easy
- Rule-based German morphology plus explicit common irregular forms
- Shared `Lang4SelfCore`, ready for later iOS and server targets

Run the core test suite with:

```sh
swift test
```

Build the actual app bundle from Terminal with:

```sh
./scripts/build-macos.sh
```

Stop, rebuild, and relaunch the development app with:

```sh
./scripts/reload-macos.sh
```

Install the release app on the Desktop and the CLI in `~/.local/bin`:

```sh
./scripts/install.sh
```

CLI examples:

```sh
lang4self                 # open the app
lang4self Haus            # search the local dictionary
lang4self stats
lang4self import dict.zip
```

## dict.cc licensing

dict.cc states that its translation data is **not open-source data**. Personal use is allowed, but each user must accept its terms and download their own copy. Software using it must be GPL-compatible, and the data must not be bundled or republished. Lang4Self therefore links to the official request page and only imports the user's local file.

Code in this repository is licensed under GPL-2.0-or-later. dict.cc data is governed separately by the dict.cc terms.
