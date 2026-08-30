import AppKit
import SwiftUI
import Lang4SelfCore

struct SpeakView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var speech: SpeechRecognizer
    @EnvironmentObject private var speakShortcut: SpeakShortcutController
    @State private var isManualRecording = false
    @State private var isShowingAddedListSelection = false
    @FocusState private var focusedControl: FocusControl?
    let automaticallyFocusContent: Bool

    private enum FocusControl: Hashable { case record, results }

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
                    statusDetail
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
                    .focused($focusedControl, equals: .results)
                    .accessibilityIdentifier("speak.results")
                    .onKeyPress(.rightArrow) {
                        guard let addedListID = state.addedListID(for: entry),
                              state.wordLists.contains(where: { $0.id != addedListID })
                        else {
                            return .ignored
                        }
                        isShowingAddedListSelection = true
                        return .handled
                    }

                    spokenEntryDetail(entry)
                }
            } else {
                PlaceholderView(
                    symbol: "waveform.and.magnifyingglass",
                    title: "Say a German word or phrase",
                    detail: "Recognition and lookup stay on this Mac. Nothing is uploaded."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Speak")
        .onKeyPress(.space, phases: .repeat) { _ in
            // The AppKit monitor owns the hold gesture. Consume any repeat that
            // reaches SwiftUI so a focused control cannot emit an error beep.
            .handled
        }
        .onChange(of: speech.transcription) { _, value in
            if !value.isEmpty {
                state.search(value, immediate: true, selectFirstResult: true)
            }
        }
        .onChange(of: speech.phase) { _, phase in
            if phase == .listening, !isRecordingRequested { speech.stop() }
            if phase != .listening, phase != .requestingPermission {
                isManualRecording = false
            }
            if phase == .guess {
                focusResults()
            } else if phase == .idle || phase.isUnavailable {
                isShowingAddedListSelection = false
                DispatchQueue.main.async { focusedControl = .record }
            }
        }
        .onChange(of: state.searchResults.map(\.id)) { _, _ in
            if speech.phase == .guess { focusResults() }
        }
        .onAppear {
            if !speech.transcription.isEmpty {
                state.search(speech.transcription, immediate: true, selectFirstResult: true)
            }
            if automaticallyFocusContent {
                DispatchQueue.main.async { focusedControl = .record }
            }
        }
        .onDisappear {
            speech.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            releaseRecordingHolds()
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if speech.hasRecordingPermission {
                holdToRecordControl
            } else {
                permissionSetupControl
            }

            if speech.phase == .requestingPermission || speech.phase == .processing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var permissionSetupControl: some View {
        Button(action: speech.requestPermissions) {
            HStack(spacing: 8) {
                Label("Request speech access", systemImage: "lock.open.fill")
                    .lineLimit(1)
                KeyboardShortcutHint(.returnKey)
                    .accessibilityHidden(true)
            }
            .fontWeight(.semibold)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 180)
        }
        .buttonStyle(SpeakActionButtonStyle(isListening: false))
        .controlSize(.large)
        .disabled(speech.phase == .requestingPermission || speakShortcut.isSpaceHeld)
        .keyboardShortcut(.return, modifiers: [])
        .focusable()
        .focused($focusedControl, equals: .record)
        .focusEffectDisabled()
        .accessibilityIdentifier("speak.permission-setup")
        .accessibilityLabel("Request speech access")
        .accessibilityHint("Allow microphone and Speech Recognition access without starting a recording")
    }

    @ViewBuilder
    private func spokenEntryDetail(_ entry: DictionaryEntry) -> some View {
        if speech.phase == .guess {
            EntryDetailView(
                entry: entry,
                addLabel: addButtonTitle,
                addShortcut: .returnKey,
                addShortcutModifiers: [],
                addAccessibilityIdentifier: "speak.add-selected",
                wordLists: state.wordLists,
                addedListID: state.addedListID(for: entry),
                isShowingListSelection: $isShowingAddedListSelection,
                switchAddedListAction: { await state.switchListForAddedEntry(entry, to: $0) },
                didFinishListSelection: focusResults,
                addAction: { state.addToPersonalDictionary(entry) }
            )
        } else {
            EntryDetailView(entry: entry)
        }
    }

    private var holdToRecordControl: some View {
        Button(action: toggleManualRecording) {
            Label(holdControlTitle, systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                .fontWeight(.semibold)
                .frame(width: 180)
        }
        .buttonStyle(SpeakActionButtonStyle(isListening: speech.isListening))
        .controlSize(.large)
        .focusable()
        .focused($focusedControl, equals: .record)
        .focusEffectDisabled()
        .overlay {
            Capsule()
                .strokeBorder(
                    focusedControl == .record && !speakShortcut.isSpaceHeld
                        ? Color(nsColor: .keyboardFocusIndicatorColor)
                        : .clear,
                    lineWidth: 3
                )
                .padding(2)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("speak.record")
        .accessibilityLabel(speech.isListening ? "Stop recording" : "Start recording")
        .accessibilityHint("Press the button, or hold Space and release it to stop")
    }

    private var statusTitle: String {
        if !speech.hasRecordingPermission {
            return switch speech.phase {
            case .requestingPermission: "Requesting speech access…"
            case .unavailable: "Speech setup needed"
            default: "Speech access needed"
            }
        }
        return switch speech.phase {
        case .idle: "Hold Space to speak"
        case .requestingPermission: "Checking local speech access…"
        case .listening: "Listening…"
        case .processing: "Recognizing…"
        case .guess: "Choose words to add"
        case .unavailable: "Speech setup needed"
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        if !speech.hasRecordingPermission {
            if case .unavailable(let message) = speech.phase {
                Text(message)
            } else if speech.phase == .requestingPermission {
                Text("Respond to the macOS permission prompts. Recording will not start yet.")
            } else {
                Text("Microphone and Speech Recognition access are required.")
            }
        } else if case .unavailable(let message) = speech.phase {
            Text(message)
        } else if speech.phase == .guess {
            HStack(spacing: 5) {
                Text("Select a match and use")
                KeyboardShortcutHint(.returnKey)
                Text("to add it · Choose another match to add more")
            }
        } else {
            Text("Hold Space while speaking · Release to look up")
        }
    }

    private var holdControlTitle: String {
        return switch speech.phase {
        case .requestingPermission: speakShortcut.isSpaceHeld ? "Keep holding Space…" : "Cancel recording"
        case .listening: speakShortcut.isSpaceHeld ? "Release Space to finish" : "Stop recording"
        case .processing: "Record again"
        case .idle, .guess, .unavailable: "Hold Space to record"
        }
    }

    private var addButtonTitle: String {
        state.selectedEntry?.kind == .phrase ? "Add phrase" : "Add word"
    }

    private var isRecordingRequested: Bool {
        speakShortcut.isSpaceHeld || isManualRecording
    }

    private func releaseRecordingHolds() {
        let wasRecording = isRecordingRequested
        speakShortcut.cancelSpaceHold()
        isManualRecording = false
        if wasRecording { speech.stop() }
    }

    private func recordingRequestChanged(wasRecording: Bool) {
        if !wasRecording, isRecordingRequested {
            switch speech.phase {
            case .idle, .unavailable:
                speech.start()
            case .processing, .guess:
                speech.rerecord()
            case .requestingPermission, .listening:
                break
            }
        } else if wasRecording, !isRecordingRequested {
            speech.stop()
        }
    }

    private func toggleManualRecording() {
        guard speech.hasRecordingPermission, !speakShortcut.isSpaceHeld else { return }
        let wasRecording = isRecordingRequested
        isManualRecording.toggle()
        recordingRequestChanged(wasRecording: wasRecording)
    }

    private func focusResults() {
        guard !state.searchResults.isEmpty else { return }
        DispatchQueue.main.async { focusedControl = .results }
    }
}

private struct SpeakActionButtonStyle: ButtonStyle {
    let isListening: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(isListening ? Color.red : Color.accentColor, in: Capsule())
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(Capsule())
    }
}

private extension SpeechRecognizer.Phase {
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}
