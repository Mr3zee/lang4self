# Architecture

`Lang4SelfCore` owns domain models, dict.cc parsing, morphology, SQLite storage, FTS search, and spaced repetition. It contains no UI or speech code.

`Apps/macOS/Lang4Self` owns SwiftUI views and the macOS on-device speech adapter. `AppState` is the UI boundary around the actor-isolated local store.

`Templates/iOS` and `Templates/Server` are intentionally disconnected. They document the later entry points without enabling sync or adding a server dependency today.

## Data flow

```text
dict.cc user download ──stream import──> SQLite + FTS5
                                             │
microphone ──local German Speech──> query ───┤
                                             ▼
                                      confirmed card
                                             │
                                             ▼
                                      review scheduler
```

The personal card stores a snapshot of the German/English pair. Re-importing or replacing dictionary rows therefore cannot destroy learned words.

Morphology is computed locally. Common irregular verbs/adjectives are explicit; other forms use German regular-form rules and are marked **estimated** in the UI.
