import AppKit
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
        appDelegate.isUITesting = dependencies.isUITesting
    }

    var body: some Scene {
        Window("Lang4Self", id: "main") {
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
            if dependencies.isUITesting {
                UITestingCommands()
            }
        }
    }
}

@MainActor
private final class Lang4SelfDependencies: ObservableObject {
    let isUITesting: Bool
    let state: AppState?
    let speech: SpeechRecognizer
    let speakShortcut: SpeakShortcutController?
    let startupFailure: String?

    init(processInfo: ProcessInfo, settingsDefaults: UserDefaults) {
        let isUITesting = processInfo.arguments.contains("--ui-testing")
        self.isUITesting = isUITesting
        speech = SpeechRecognizer(
            isUITesting: isUITesting,
            simulatesUndeterminedPermissions: processInfo.arguments.contains("--ui-testing-speech-permission-setup")
        )
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
    var isUITesting = false
    private var shortcutKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        speakShortcut?.startMonitoring()
        installShortcutKeyMonitor()

        guard isUITesting else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard !NSApp.windows.contains(where: \.isVisible),
                  let openMainWindow = NSApp.mainMenu?.items
                    .compactMap(\.submenu)
                    .flatMap(\.items)
                    .first(where: { $0.title == "Open Main Window for UI Testing" }),
                  let action = openMainWindow.action
            else { return }
            NSApp.sendAction(action, to: openMainWindow.target, from: openMainWindow)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillResignActive(_ notification: Notification) {
        speakShortcut?.cancelSpaceHold()
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
        if let shortcutKeyMonitor { NSEvent.removeMonitor(shortcutKeyMonitor) }
        shortcutKeyMonitor = nil
    }

    private func installShortcutKeyMonitor() {
        guard shortcutKeyMonitor == nil else { return }
        shortcutKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.command),
                  modifiers.intersection([.control, .option]).isEmpty,
                  event.charactersIgnoringModifiers.map({ $0 == "/" || $0 == "?" }) == true
            else { return event }

            if !event.isARepeat {
                NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
            }
            return nil
        }
    }
}

private struct UITestingCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("UI Testing") {
            Button("Open Main Window for UI Testing") {
                openWindow(id: "main")
            }
        }
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

        CommandGroup(replacing: .newItem) {
            Button("New List") {
                NotificationCenter.default.post(name: .createWordList, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
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

        // Route changes mount their destination asynchronously. A short delay
        // prevents the notification from racing the new view on slower Macs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }
}
