import SwiftUI
import Lang4SelfCore

struct SpeakView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var speech = SpeechRecognizer()
    @FocusState private var keyboardActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(speech.isListening ? Color.red.opacity(0.14) : Color.accentColor.opacity(0.12))
                        .frame(width: 92, height: 92)
                    Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(speech.isListening ? Color.red : Color.accentColor)
                        .symbolEffect(.variableColor.iterative, isActive: speech.isListening)
                }

                Text(statusTitle)
                    .font(.title2.weight(.bold))

                if !speech.transcription.isEmpty {
                    Text(speech.transcription)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .textSelection(.enabled)
                } else {
                    Text(statusDetail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                controls
            }
            .padding(26)

            Divider()

            if let entry = state.selectedEntry, !speech.transcription.isEmpty {
                HSplitView {
                    List(state.searchResults.prefix(8), selection: $state.selectedEntry) { result in
                        EntryRow(entry: result).tag(result)
                    }
                    .frame(minWidth: 260, idealWidth: 310)

                    EntryDetailView(entry: entry)
                }
            } else {
                PlaceholderView(
                    symbol: "waveform.and.magnifyingglass",
                    title: "Say one German word",
                    detail: "Recognition and lookup stay on this Mac. Nothing is uploaded."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Speak")
        .focusable()
        .focused($keyboardActive)
        .onAppear { keyboardActive = true }
        .onChange(of: speech.transcription) { _, value in
            if !value.isEmpty { state.search(value, immediate: true) }
        }
        .onKeyPress(.return) {
            confirm()
            return .handled
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch speech.phase {
        case .idle, .unavailable:
            Button {
                speech.start()
            } label: {
                Label("Record", systemImage: "space")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.space, modifiers: [])
        case .requestingPermission:
            ProgressView().controlSize(.small)
        case .listening:
            Button("Finish recording") { speech.acceptCurrentGuess() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.space, modifiers: [])
        case .guess:
            HStack {
                Button("Re-record  Space") { speech.rerecord() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.space, modifiers: [])
                Button("Add word  Return") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.selectedEntry == nil)
            }
        }
    }

    private var statusTitle: String {
        switch speech.phase {
        case .idle: "Press Space to speak"
        case .requestingPermission: "Checking local speech access…"
        case .listening: speech.transcription.isEmpty ? "Listening…" : "Is this right?"
        case .guess: "Confirm the best match"
        case .unavailable: "Speech setup needed"
        }
    }

    private var statusDetail: String {
        if case .unavailable(let message) = speech.phase { return message }
        return "Space starts recording · Return confirms · Space again re-records"
    }

    private func confirm() {
        guard !speech.transcription.isEmpty, state.selectedEntry != nil else { return }
        speech.acceptCurrentGuess()
        state.confirmSpokenEntry()
        speech.reset()
    }
}
