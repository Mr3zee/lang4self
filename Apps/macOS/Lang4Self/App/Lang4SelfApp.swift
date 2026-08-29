import AppKit
import SwiftUI

@main
struct Lang4SelfApp: App {
    @NSApplicationDelegateAdaptor(Lang4SelfAppDelegate.self) private var appDelegate
    @StateObject private var state: AppState

    init() {
        do {
            let initialState = try AppState()
            _state = StateObject(wrappedValue: initialState)
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await LMStudioService.shared.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

private struct Lang4SelfCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(Array(AppRoute.allCases.enumerated()), id: \.element.id) { index, route in
                Button(route.title) { state.route = route }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        CommandGroup(after: .textEditing) {
            Button("Search Dictionary") {
                state.route = .dictionary
                NotificationCenter.default.post(name: .focusDictionarySearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}
