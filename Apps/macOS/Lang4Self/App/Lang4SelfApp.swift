import AppKit
import Carbon
import SwiftUI
import Lang4SelfCore

@main
struct Lang4SelfApp: App {
    @NSApplicationDelegateAdaptor(Lang4SelfAppDelegate.self) private var appDelegate
    @StateObject private var state: AppState

    init() {
        do {
            let environment = ProcessInfo.processInfo.environment
            let testStore: LocalStore?
            if let path = environment["LANG4SELF_UI_TEST_DATABASE"] {
                testStore = try LocalStore(url: URL(fileURLWithPath: path))
            } else {
                testStore = nil
            }
            let initialState = try AppState(store: testStore)
            _state = StateObject(wrappedValue: initialState)
            appDelegate.appState = initialState
        } catch {
            fatalError("Lang4Self could not start: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1_120, height: 740)
        .commands {
            Lang4SelfCommands(state: state)
        }
    }
}

private final class Lang4SelfAppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var shortcutHotKey: EventHotKeyRef?
    private var shortcutHotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installShortcutHotKeyHandler()
        registerShortcutHotKey()

        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard !NSApp.windows.contains(where: \.isVisible),
                  let newWindow = NSApp.mainMenu?.items
                    .compactMap(\.submenu)
                    .flatMap(\.items)
                    .first(where: { $0.title == "New Window" }),
                  let action = newWindow.action
            else { return }
            NSApp.sendAction(action, to: newWindow.target, from: newWindow)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        registerShortcutHotKey()
    }

    func applicationWillResignActive(_ notification: Notification) {
        unregisterShortcutHotKey()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor [weak appState] in
            await appState?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterShortcutHotKey()
        if let shortcutHotKeyHandler { RemoveEventHandler(shortcutHotKeyHandler) }
        shortcutHotKeyHandler = nil
    }

    private func installShortcutHotKeyHandler() {
        guard shortcutHotKeyHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                return noErr
            },
            1,
            &eventType,
            nil,
            &shortcutHotKeyHandler
        )
    }

    private func registerShortcutHotKey() {
        guard shortcutHotKey == nil else { return }
        let identifier = EventHotKeyID(signature: OSType(0x4C345348), id: 1) // L4SH
        RegisterEventHotKey(
            UInt32(kVK_ANSI_Slash),
            UInt32(cmdKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &shortcutHotKey
        )
    }

    private func unregisterShortcutHotKey() {
        if let shortcutHotKey { UnregisterEventHotKey(shortcutHotKey) }
        shortcutHotKey = nil
    }

}

private struct Lang4SelfCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                state.route = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("New List") {
                NotificationCenter.default.post(name: .createWordList, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(state.route != .library)
        }

        CommandMenu("Navigate") {
            ForEach(Array(AppRoute.allCases.enumerated()), id: \.element.id) { index, route in
                Button(route.title) { state.route = route }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }

        CommandGroup(after: .textEditing) {
            Button("Find") { focusSearch() }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts…") {
                state.isShowingKeyboardShortcuts = true
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }

    private func focusSearch() {
        let notification: Notification.Name
        if state.route == .library {
            notification = .focusLibrarySearch
        } else {
            state.route = .dictionary
            notification = .focusDictionarySearch
        }

        // Wait until the destination view is mounted before moving focus.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }
}
