# iOS target template (inactive)

This is a future app entry point, intentionally not part of the current Xcode project.

When iOS work starts:

1. Add an iOS app target with deployment target iOS 17+.
2. Add `Lang4SelfCore` as a target dependency.
3. Move reusable SwiftUI components into a shared UI target.
4. Add the iOS microphone and speech usage descriptions.
5. Keep local storage authoritative; introduce sync only as an explicit product decision.
