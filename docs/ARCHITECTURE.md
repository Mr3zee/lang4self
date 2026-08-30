# Architecture

`Lang4SelfCore` owns domain models, dict.cc parsing, morphology, SQLite storage, FTS search, and spaced repetition. It contains no UI or speech code. `LocalStoreSchema` is the only schema/migration owner; `LocalStore` implements runtime data capabilities.

`Apps/macOS/Lang4Self` owns SwiftUI views, the macOS on-device speech adapter, and the localhost-only LM Studio adapter. `AppState` is the UI boundary around the actor-isolated local store. Production dependencies are created in `Lang4SelfApp`; `AppState` talks to storage, dictionary-file preparation, sentence generation, and settings through narrow protocols. Runtime flags, clocks, calendars, preferences, and speech configuration enter through this composition root rather than hidden globals.

`Templates/iOS` and `Templates/Server` are intentionally disconnected. They document the later entry points without enabling sync or adding a server dependency today.

## Data flow

```text
dict.cc user download ──stream import────────> SQLite + FTS5
Lector SQLite download ──explanation import──>      │
microphone ──local German Speech──────> query ──────┤
                                                    ▼
                                             confirmed card
                                                    │
                                                    ▼
                                             review scheduler
```

Sentence generation reads a bounded snapshot of the selected word list, starts LM Studio's localhost server, and loads a dedicated `lang4self-sentences` model instance. Structured model output is validated against the source card IDs before it reaches the UI. Saved sentences and their word-to-card mappings live in SQLite. Normal app termination unloads the dedicated model instance.

The personal card stores a snapshot of the German word and its available English/Russian translations. Re-importing or replacing dictionary rows therefore cannot destroy learned words.

Wiktionary explanations are imported into a separate table and joined to dict.cc results by the exact German spelling and part of speech. This avoids pretending that the two sources' senses align one-to-one. Explanations identical to an existing translation are suppressed in the UI.

Morphology is computed locally. Common irregular verbs/adjectives are explicit; other forms use German regular-form rules and are marked **estimated** in the UI.

## Evolution boundaries

- Shared import preparation lives in `Lang4SelfCore`; the app, CLI, and importer use the same implementation.
- SQLite uses ordered `PRAGMA user_version` migrations. A newer database is rejected instead of being opened by code that cannot understand it.
- Multi-write domain operations are transactions. A failed review cannot update scheduling without also recording its review log.
- Calendar-day behavior uses an injected calendar instead of Unix/UTC day arithmetic.
- SwiftUI views contain presentation and interaction only. Filesystem, process, database, and model-server behavior stays behind injected adapters.
- Large coordinators are not extension points. New capabilities belong in focused types and are exposed through narrow protocols.
