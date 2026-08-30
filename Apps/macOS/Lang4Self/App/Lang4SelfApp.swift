import AppKit
import Carbon
import SwiftUI
import Lang4SelfCore

@main
struct Lang4SelfApp: App {
    @NSApplicationDelegateAdaptor(Lang4SelfAppDelegate.self) private var appDelegate
    @StateObject private var dependencies: Lang4SelfDependencies

    init() {
        let dependencies = Lang4SelfDependencies(
            processInfo: .processInfo,
            settingsDefaults: .standard
        )
        _dependencies = StateObject(wrappedValue: dependencies)
        appDelegate.appState = dependencies.state
        appDelegate.speakShortcut = dependencies.speakShortcut
    }

    var body: some Scene {
        WindowGroup {
            if let state = dependencies.state, let speakShortcut = dependencies.speakShortcut {
                RootView()
                    .environmentObject(state)
                    .environmentObject(dependencies.speech)
                    .environmentObject(speakShortcut)
            } else {
                StartupFailureView(message: dependencies.startupFailure ?? "The application could not start.")
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1_120, height: 740)
        .commands {
            if let state = dependencies.state {
                Lang4SelfCommands(state: state)
            }
        }
    }
}

@MainActor
private final class Lang4SelfDependencies: ObservableObject {
    let state: AppState?
    let speech: SpeechRecognizer
    let speakShortcut: SpeakShortcutController?
    let startupFailure: String?

    init(processInfo: ProcessInfo, settingsDefaults: UserDefaults) {
        let isUITesting = processInfo.arguments.contains("--ui-testing")
        speech = SpeechRecognizer(isUITesting: isUITesting)
        do {
            let databaseURL = processInfo.environment["LANG4SELF_UI_TEST_DATABASE"]
                .map(URL.init(fileURLWithPath:))
            let store = try LocalStore(url: databaseURL, now: { .now })
            let settingsStore = UserDefaultsLMStudioSettingsStore(defaults: settingsDefaults)
            let state = AppState(
                store: store,
                sentenceGenerator: LMStudioService(),
                dictionaryFilePreparer: SystemDictionaryFilePreparer(),
                settingsStore: settingsStore,
                isUITesting: isUITesting,
                now: { .now },
                calendar: .autoupdatingCurrent
            )
            self.state = state
            speakShortcut = SpeakShortcutController(
                router: state,
                speech: speech,
                holdDelay: 0.18
            )
            startupFailure = nil
        } catch {
            state = nil
            speakShortcut = nil
            startupFailure = error.localizedDescription
        }
    }
}

private struct StartupFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Lang4Self could not start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .padding(32)
    }
}

@MainActor
private final class Lang4SelfAppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    var speakShortcut: SpeakShortcutController?
    private var shortcutHotKey: EventHotKeyRef?
    private var shortcutHotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        speakShortcut?.startMonitoring()
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
        speakShortcut?.releaseSpaceHold()
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
        speakShortcut?.stopMonitoring()
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
