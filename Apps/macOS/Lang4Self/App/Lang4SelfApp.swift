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
        appDelegate.pronunciationShortcut = dependencies.pronunciationShortcut
        appDelegate.germanSpeech = dependencies.germanSpeech
        appDelegate.scrollbarStyler = OverlayScrollbarStyler(notificationCenter: .default)
        appDelegate.isUITesting = dependencies.isUITesting
    }

    var body: some Scene {
        Window("Lang4Self", id: "main") {
            if let state = dependencies.state, let voiceSearchShortcut = dependencies.voiceSearchShortcut {
                RootView()
                    .environmentObject(state)
                    .environmentObject(dependencies.speech)
                    .environmentObject(voiceSearchShortcut)
                    .environmentObject(dependencies.germanSpeech)
                    .hostsDictionaryTranslation(using: dependencies.dictionaryTranslator)
            } else {
                StartupFailureView(message: dependencies.startupFailure ?? "The application could not start.")
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1_121, height: 939)
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
    let germanSpeech: GermanSpeechController
    let dictionaryTranslator: any DictionaryTranslating
    let voiceSearchShortcut: VoiceSearchShortcutController?
    let pronunciationShortcut: DoubleShiftShortcutController
    let startupFailure: String?

    init(processInfo: ProcessInfo, settingsDefaults: UserDefaults) {
        let isUITesting = processInfo.arguments.contains("--ui-testing")
        self.isUITesting = isUITesting
        speech = SpeechRecognizer(
            isUITesting: isUITesting,
            simulatesUndeterminedPermissions: processInfo.arguments.contains("--ui-testing-speech-permission-setup"),
            uiTestingAlternativeCount: processInfo.arguments.contains("--ui-testing-empty-voice-result")
                ? 0
                : processInfo.arguments.contains("--ui-testing-single-voice-alternative") ? 1 : 3
        )
        let germanSpeech = GermanSpeechController(
            synthesizer: isUITesting
                ? UITestingGermanSpeechSynthesizer()
                : AppleGermanSpeechSynthesizer()
        )
        self.germanSpeech = germanSpeech
        pronunciationShortcut = DoubleShiftShortcutController { [weak germanSpeech] in
            germanSpeech?.speakTarget()
        }
        if isUITesting && processInfo.arguments.contains("--ui-testing-translation-fallback") {
            dictionaryTranslator = UITestingDictionaryTranslator()
        } else if isUITesting {
            dictionaryTranslator = UnavailableDictionaryTranslator()
        } else if #available(macOS 15.0, *) {
            dictionaryTranslator = AppleLocalTranslator()
        } else {
            dictionaryTranslator = UnavailableDictionaryTranslator()
        }
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
                dictionarySearch: DictionarySearchService(
                    index: store,
                    translator: dictionaryTranslator
                ),
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
    var pronunciationShortcut: DoubleShiftShortcutController?
    var germanSpeech: GermanSpeechController?
    var scrollbarStyler: (any AppScrollbarStyling)?
    var isUITesting = false
    private var shortcutKeyMonitor: Any?
    private var uiTestingInputObserver: NSObjectProtocol?
    private var uiTestingDoubleShiftObserver: NSObjectProtocol?
    private var uiTestingDisableMonitorObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let application = notification.object as? NSApplication {
            scrollbarStyler?.start(application: application)
        }
        voiceSearchShortcut?.startMonitoring()
        pronunciationShortcut?.startMonitoring()
        installShortcutKeyMonitor()

        guard isUITesting else { return }
        uiTestingInputObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("Lang4SelfUITestingSimulateHeldSpace"),
            object: nil,
            queue: .main
        ) { _ in
            UITestingInput.postHeldSpaceWithRepeats()
        }
        uiTestingDoubleShiftObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("Lang4SelfUITestingSimulateDoubleShift"),
            object: nil,
            queue: .main
        ) { _ in
            UITestingInput.postDoubleShift()
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
        pronunciationShortcut?.reset()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor [weak appState] in
            await appState?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        scrollbarStyler?.stop()
        voiceSearchShortcut?.stopMonitoring()
        pronunciationShortcut?.stopMonitoring()
        germanSpeech?.stop()
        if let shortcutKeyMonitor { NSEvent.removeMonitor(shortcutKeyMonitor) }
        shortcutKeyMonitor = nil
        if let uiTestingInputObserver {
            DistributedNotificationCenter.default().removeObserver(uiTestingInputObserver)
        }
        uiTestingInputObserver = nil
        if let uiTestingDoubleShiftObserver {
            DistributedNotificationCenter.default().removeObserver(uiTestingDoubleShiftObserver)
        }
        uiTestingDoubleShiftObserver = nil
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
                cycleReviewMode: { [weak self] offset in
                    guard self?.appState?.route == .review else { return false }
                    NotificationCenter.default.post(
                        name: offset < 0 ? .previousReviewMode : .nextReviewMode,
                        object: nil
                    )
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
    let cycleReviewMode: (Int) -> Bool
    let isEditingText: () -> Bool

    init(
        openSettings: @escaping () -> Void,
        showKeyboardShortcuts: @escaping () -> Void,
        undo: @escaping () -> Bool = { false },
        redo: @escaping () -> Bool = { false },
        cycleReviewMode: @escaping (Int) -> Bool = { _ in false },
        isEditingText: @escaping () -> Bool = { false }
    ) {
        self.openSettings = openSettings
        self.showKeyboardShortcuts = showKeyboardShortcuts
        self.undo = undo
        self.redo = redo
        self.cycleReviewMode = cycleReviewMode
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
        case "[" where !modifiers.contains(.shift),
             "]" where !modifiers.contains(.shift):
            guard !event.isARepeat else { return event }
            let handled = cycleReviewMode(characters == "[" ? -1 : 1)
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

    static func postDoubleShift() {
        NSApp.activate()
        NSApp.mainWindow?.makeKey()
        postShiftEvent(isDown: true, after: 0.05)
        postShiftEvent(isDown: false, after: 0.10)
        postShiftEvent(isDown: true, after: 0.15)
        postShiftEvent(isDown: false, after: 0.20)
    }

    private static func postShiftEvent(isDown: Bool, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let event = NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: isDown ? .shift : [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: NSApp.mainWindow?.windowNumber ?? 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 56
            ) else { return }
            NSApp.postEvent(event, atStart: false)
        }
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

@MainActor
protocol AppScrollbarStyling: AnyObject {
    func start(application: NSApplication)
    func stop()
}

@MainActor
final class OverlayScrollbarStyler: AppScrollbarStyling {
    private let notificationCenter: NotificationCenter
    private weak var application: NSApplication?
    private var updateObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
    }

    func start(application: NSApplication) {
        stop()
        self.application = application
        styleScrollViews(in: application.windows)
        updateObserver = notificationCenter.addObserver(
            forName: NSApplication.didUpdateNotification,
            object: application,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let application = self.application else { return }
                self.styleScrollViews(in: application.windows)
            }
        }
    }

    func stop() {
        if let updateObserver {
            notificationCenter.removeObserver(updateObserver)
        }
        updateObserver = nil
        application = nil
    }

    func styleScrollViews(in windows: [NSWindow]) {
        for window in windows {
            guard let contentView = window.contentView else { continue }
            Self.styleScrollViews(in: contentView)
        }
    }

    static func styleScrollViews(in rootView: NSView) {
        if let scrollView = rootView as? NSScrollView {
            style(scrollView)
        }
        for subview in rootView.subviews {
            styleScrollViews(in: subview)
        }
    }

    private static func style(_ scrollView: NSScrollView) {
        var needsTiling = false
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
            needsTiling = true
        }
        for scroller in [scrollView.verticalScroller, scrollView.horizontalScroller].compactMap({ $0 }) {
            if scroller.controlSize != .small {
                scroller.controlSize = .small
                needsTiling = true
            }
        }
        if needsTiling {
            scrollView.tile()
        }
    }
}

@MainActor
private final class UITestingGermanSpeechSynthesizer: GermanSpeechSynthesizing {
    func speak(_ text: String) {}
    func stop() {}
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
                Button(route.title) {
                    NotificationCenter.default.post(name: .focusSidebar, object: nil)
                    state.route = route
                }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }

        CommandGroup(after: .textEditing) {
            Button("Find") { focusSearch() }
            .keyboardShortcut("f", modifiers: .command)

            Button("Previous Review Mode") {
                NotificationCenter.default.post(name: .previousReviewMode, object: nil)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(state.route != .review)

            Button("Next Review Mode") {
                NotificationCenter.default.post(name: .nextReviewMode, object: nil)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(state.route != .review)
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
