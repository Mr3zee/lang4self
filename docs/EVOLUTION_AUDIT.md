# Evolution audit

## Fixed

| Risk | Change |
|---|---|
| `AppState` depended on a concrete SQLite actor and a process-wide LM Studio singleton. | Added injected `AppDataStore` and `SentenceGenerating` boundaries; app shutdown now targets the injected instance. |
| ZIP preparation was implemented separately by the app, CLI, and importer. | Moved it to one tested `Lang4SelfCore` utility used by all three entry points. |
| Database changes were inferred from columns with no schema version or forward-compatibility check. | Added transactional schema versioning, legacy adoption, and rejection/tests for newer schemas. |
| Preferences and UI-test detection were hidden globals inside app state. | Made settings storage and UI-test mode injectable while retaining production defaults. |
| `AppState.init` silently started asynchronous database work. | Moved startup to an explicit, idempotent `bootstrap()` lifecycle call from the root view. |
| Three coordinator files are already broad (`LocalStore`, `AppState`, `LMStudioService`). | New repository rules prevent adding unrelated responsibilities and require focused types behind capability protocols. |

## Review trigger

Revisit a boundary when a feature needs to edit more than one coordinator, an integration is used by a second entry point, or a test needs a real user service. That is the signal to extract a focused capability before adding the feature.
