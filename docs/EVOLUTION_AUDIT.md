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
| Production fallbacks in `AppState` still hid SQLite, preferences, process arguments, and LM Studio construction. | Made the composition root create and inject every production dependency; moved preference persistence to `LMStudioSettingsStoring`. |
| Speech test mode read global process arguments inside the speech adapter. | Injected speech configuration from the composition root. |
| A review updated its card before inserting its log, allowing partial persistence. | Wrapped both writes in one transaction and added a forced-failure rollback test. |
| Review streaks used UTC epoch days while “reviews today” used the supplied calendar. | Made both calculations calendar-aware and bounded “today” on both sides. |
| Schema migration code occupied the runtime store coordinator. | Extracted `LocalStoreSchema` as the single migration owner without changing schema version 1. |
| Creation timestamps and collection limits were hidden or unchecked. | Added an injectable store clock, deterministic tests, and safe non-positive/clamped limits. |
| Database startup errors terminated the app with `fatalError`. | Added a composition container and a non-destructive startup error screen. |
| `AppState` invoked the concrete ZIP/process utility directly. | Injected `DictionaryFilePreparing`; app, CLI, and importer compose the system implementation. |

## Review trigger

Revisit a boundary when a feature needs to edit more than one coordinator, an integration is used by a second entry point, or a test needs a real user service. That is the signal to extract a focused capability before adding the feature.
