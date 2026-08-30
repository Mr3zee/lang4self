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
        appDelegate.voiceSearchShortcut = dependencies.voiceSearchShortcut
        appDelegate.isUITesting = dependencies.isUITesting
    }

    var body: some Scene {
        Window("Lang4Self", id: "main") {
            if let state = dependencies.state, let voiceSearchShortcut = dependencies.voiceSearchShortcut {
                RootView()
                    .environmentObject(state)
                    .environmentObject(dependencies.speech)
                    .environmentObject(voiceSearchShortcut)
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
    let voiceSearchShortcut: VoiceSearchShortcutController?
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
            let uiTestingDictionaryURLs = [
                processInfo.environment["LANG4SELF_UI_TEST_ENGLISH_DICTIONARY"],
                processInfo.environment["LANG4SELF_UI_TEST_RUSSIAN_DICTIONARY"]
            ]
                .compactMap { $0 }
                .map(URL.init(fileURLWithPath:))
            let store = try LocalStore(url: databaseURL, now: { .now })
            let settingsStore = UserDefaultsLMStudioSettingsStore(defaults: settingsDefaults)
            let udpipeConfiguration = URLSessionConfiguration.ephemeral
            udpipeConfiguration.timeoutIntervalForRequest = 60
            udpipeConfiguration.timeoutIntervalForResource = 90
            udpipeConfiguration.waitsForConnectivity = false
            let state = AppState(
                store: store,
                sentenceGenerator: LMStudioService(),
                sentenceAnalyzer: UDPipeSentenceAnalyzer(
                    session: URLSession(configuration: udpipeConfiguration)
                ),
                dictionaryFilePreparer: SystemDictionaryFilePreparer(),
                settingsStore: settingsStore,
                isUITesting: isUITesting,
                uiTestingDictionaryURLs: uiTestingDictionaryURLs,
                now: { .now },
                calendar: .autoupdatingCurrent
            )
            self.state = state
            let reportForwardedSpaceEvent: () -> Void = isUITesting
                ? {
                    DistributedNotificationCenter.default().postNotificationName(
                        Notification.Name("Lang4SelfUITestingSpaceEventLeaked"),
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                }
                : {}
            voiceSearchShortcut = VoiceSearchShortcutController(
                router: state,
                speech: speech,
                context: AppKitVoiceSearchShortcutContext(application: .shared),
                holdDelay: 0.18,
                onForwardedSpaceEvent: reportForwardedSpaceEvent
            )
            startupFailure = nil
        } catch {
            state = nil
            voiceSearchShortcut = nil
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
    var voiceSearchShortcut: VoiceSearchShortcutController?
    var isUITesting = false
    private var shortcutKeyMonitor: Any?
    private var uiTestingInputObserver: NSObjectProtocol?
    private var uiTestingDisableMonitorObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        voiceSearchShortcut?.startMonitoring()
        installShortcutKeyMonitor()

        guard isUITesting else { return }
        uiTestingInputObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("Lang4SelfUITestingSimulateHeldSpace"),
            object: nil,
            queue: .main
        ) { _ in
            UITestingInput.postHeldSpaceWithRepeats()
        }
        uiTestingDisableMonitorObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("Lang4SelfUITestingDisableSpaceMonitor"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.voiceSearchShortcut?.stopMonitoring()
            }
        }
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
        voiceSearchShortcut?.cancelSpaceHold()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor [weak appState] in
            await appState?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        voiceSearchShortcut?.stopMonitoring()
        if let shortcutKeyMonitor { NSEvent.removeMonitor(shortcutKeyMonitor) }
        shortcutKeyMonitor = nil
        if let uiTestingInputObserver {
            DistributedNotificationCenter.default().removeObserver(uiTestingInputObserver)
        }
        uiTestingInputObserver = nil
        if let uiTestingDisableMonitorObserver {
            DistributedNotificationCenter.default().removeObserver(uiTestingDisableMonitorObserver)
        }
        uiTestingDisableMonitorObserver = nil
    }

    private func installShortcutKeyMonitor() {
        guard shortcutKeyMonitor == nil else { return }
        shortcutKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            AppShortcutKeyHandler(
                openSettings: { [weak self] in self?.appState?.route = .settings },
                showKeyboardShortcuts: {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                },
                undo: { [weak self] in
                    guard let state = self?.appState, state.undoHistory.canUndo else { return false }
                    state.undo()
                    return true
                },
                redo: { [weak self] in
                    guard let state = self?.appState, state.undoHistory.canRedo else { return false }
                    state.redo()
                    return true
                },
                isEditingText: { event.window?.firstResponder is NSTextView }
            )
            .handle(event)
        }
    }

}

@MainActor
struct AppShortcutKeyHandler {
    let openSettings: () -> Void
    let showKeyboardShortcuts: () -> Void
    let undo: () -> Bool
    let redo: () -> Bool
    let isEditingText: () -> Bool

    init(
        openSettings: @escaping () -> Void,
        showKeyboardShortcuts: @escaping () -> Void,
        undo: @escaping () -> Bool = { false },
        redo: @escaping () -> Bool = { false },
        isEditingText: @escaping () -> Bool = { false }
    ) {
        self.openSettings = openSettings
        self.showKeyboardShortcuts = showKeyboardShortcuts
        self.undo = undo
        self.redo = redo
        self.isEditingText = isEditingText
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              modifiers.intersection([.control, .option]).isEmpty,
              let characters = event.charactersIgnoringModifiers
        else { return event }

        switch characters.lowercased() {
        case "," where !modifiers.contains(.shift):
            if !event.isARepeat { openSettings() }
            return nil
        case "/", "?":
            if !event.isARepeat { showKeyboardShortcuts() }
            return nil
        case "z" where !isEditingText():
            guard !event.isARepeat else { return nil }
            let handled = modifiers.contains(.shift) ? redo() : undo()
            return handled ? nil : event
        default:
            return event
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

private enum UITestingInput {
    static func postHeldSpaceWithRepeats() {
        NSApp.activate()
        NSApp.mainWindow?.makeKey()
        postSpaceEvent(type: .keyDown, isRepeat: false, after: 0.05)
        postSpaceEvent(type: .keyDown, isRepeat: true, after: 0.10)
        postSpaceEvent(type: .keyDown, isRepeat: true, after: 0.15)
        postSpaceEvent(type: .keyUp, isRepeat: false, after: 0.20)
    }

    private static func postSpaceEvent(
        type: NSEvent.EventType,
        isRepeat: Bool,
        after delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: NSApp.mainWindow?.windowNumber ?? 0,
                context: nil,
                characters: " ",
                charactersIgnoringModifiers: " ",
                isARepeat: isRepeat,
                keyCode: 49
            ) else { return }
            NSApp.postEvent(event, atStart: false)
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
        let routeIsChanging: Bool
        if state.route == .library {
            notification = .focusLibrarySearch
            routeIsChanging = false
        } else {
            routeIsChanging = state.route != .dictionary
            state.route = .dictionary
            notification = .focusDictionarySearch
        }

        let postFocusNotification = {
            NotificationCenter.default.post(name: notification, object: nil)
        }
        if routeIsChanging {
            // Route changes mount their destination asynchronously. A short
            // delay prevents the notification from racing the new view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: postFocusNotification)
        } else {
            DispatchQueue.main.async(execute: postFocusNotification)
        }
    }
}
