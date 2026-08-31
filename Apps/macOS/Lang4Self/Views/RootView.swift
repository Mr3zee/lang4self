import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var germanSpeech: GermanSpeechController
    @FocusState private var sidebarFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(AppRoute.allCases, selection: $state.route) { route in
                Label {
                    HStack {
                        Text(route.title)
                        Spacer()
                        if route == .review, state.stats.dueCards > 0 {
                            Text(state.stats.dueCards.formatted())
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: route.symbol)
                }
                .tag(route)
                .accessibilityIdentifier("sidebar.\(route.rawValue)")
            }
            .focused($sidebarFocused)
            .accessibilityIdentifier("sidebar.routes")
            .onKeyPress(.upArrow) {
                moveSidebarSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSidebarSelection(by: 1)
                return .handled
            }
            .onKeyPress(.return) {
                focusSelectedPageContent()
                return .handled
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 205)
            .safeAreaInset(edge: .bottom) {
                if !state.hasCompleteDictionary {
                    Button {
                        state.route = .settings
                    } label: {
                        Label("Get full dictionary", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .accessibilityIdentifier("sidebar.get-full-dictionary")
                }
            }
        } detail: {
            content
                .frame(minWidth: 650, minHeight: 500)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let banner = state.banner {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                        Text(banner)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            state.dismissBanner()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss notification")
                        .accessibilityLabel("Dismiss notification")
                        .accessibilityIdentifier("banner.dismiss")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 12, y: 4)
                    .frame(maxWidth: 420)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy, value: state.banner)
        .sheet(isPresented: $state.isShowingKeyboardShortcuts) {
            KeyboardShortcutsSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
            state.isShowingKeyboardShortcuts = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebar)) { _ in
            sidebarFocused = true
            DispatchQueue.main.async {
                sidebarFocused = false
                DispatchQueue.main.async { sidebarFocused = true }
            }
        }
        .onAppear(perform: activateGermanSpeechContext)
        .onChange(of: state.route) { _, _ in activateGermanSpeechContext() }
        .overlay(alignment: .topLeading) {
            if state.isUITestSession, state.isBootstrapComplete {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Application ready")
                    .accessibilityIdentifier("app.ready")
            }
        }
        .overlay(alignment: .topLeading) {
            if state.isUITestSession, let lastSpokenText = germanSpeech.lastSpokenText {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Last pronounced German: \(lastSpokenText)")
                    .accessibilityIdentifier("speech.last-spoken")
            }
        }
        .overlay(alignment: .topLeading) {
            if state.isUITestSession, let target = germanSpeech.target {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pronunciation target: \(target)")
                    .accessibilityIdentifier("speech.target")
            }
        }
        .task {
            await state.bootstrap()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.route {
        case .dictionary: DictionaryView(automaticallyFocusContent: !sidebarFocused)
        case .review: ReviewView(automaticallyFocusContent: !sidebarFocused)
        case .library: LibraryView(automaticallyFocusContent: !sidebarFocused)
        case .settings: SettingsView(automaticallyFocusContent: !sidebarFocused)
        }
    }

    private func moveSidebarSelection(by offset: Int) {
        guard let index = AppRoute.allCases.firstIndex(of: state.route) else { return }
        let count = AppRoute.allCases.count
        state.route = AppRoute.allCases[(index + offset + count) % count]
    }

    private func focusSelectedPageContent() {
        let notification: Notification.Name?
        switch state.route {
        case .dictionary:
            notification = .focusDictionaryContent
        case .library:
            notification = .focusLibraryContent
        case .review:
            notification = .focusReviewContent
        case .settings:
            notification = nil
        }

        if let notification {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: notification, object: nil)
            }
        }
    }

    private func activateGermanSpeechContext() {
        let context: GermanSpeechController.Context? = switch state.route {
        case .dictionary: .dictionary
        case .review: .review
        case .library: .library
        case .settings: nil
        }
        germanSpeech.activate(context)
    }
}

extension Notification.Name {
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let focusSidebar = Notification.Name("focusSidebar")
}
