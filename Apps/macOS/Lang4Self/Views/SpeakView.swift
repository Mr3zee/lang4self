import AppKit
import SwiftUI
import Lang4SelfCore

struct SpeakView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var speech = SpeechRecognizer()
    @State private var spaceMonitor: Any?
    @State private var isSpaceHeld = false
    @State private var isManualRecording = false
    @FocusState private var focusedControl: FocusControl?

    private enum FocusControl: Hashable { case record, confirm }

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
                    title: "Say a German word or phrase",
                    detail: "Recognition and lookup stay on this Mac. Nothing is uploaded."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Speak")
        .onChange(of: speech.transcription) { _, value in
            if !value.isEmpty { state.search(value, immediate: true) }
        }
        .onChange(of: speech.phase) { _, phase in
            if phase == .listening, !isRecordingRequested { speech.stop() }
            if phase != .listening, phase != .requestingPermission {
                isManualRecording = false
            }
            if phase == .guess {
                DispatchQueue.main.async { focusedControl = .confirm }
            } else if phase == .idle || phase.isUnavailable {
                DispatchQueue.main.async { focusedControl = .record }
            }
        }
        .onAppear {
            installSpaceMonitor()
            DispatchQueue.main.async { focusedControl = .record }
        }
        .onDisappear {
            removeSpaceMonitor()
            speech.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            releaseRecordingHolds()
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            holdToRecordControl

            if speech.phase == .requestingPermission || speech.phase == .processing {
                ProgressView().controlSize(.small)
            }

            if speech.phase == .guess {
                Button(addButtonTitle) { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.selectedEntry == nil)
                    .keyboardShortcut(.return, modifiers: [])
                    .focusable()
                    .focused($focusedControl, equals: .confirm)
                    .accessibilityIdentifier("speak.confirm")
            }
        }
    }

    private var holdToRecordControl: some View {
        Button(action: toggleManualRecording) {
            Label(holdControlTitle, systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(speech.isListening ? .red : .accentColor)
        .focusable()
        .focused($focusedControl, equals: .record)
        .accessibilityIdentifier("speak.record")
        .accessibilityLabel(speech.isListening ? "Stop recording" : "Start recording")
        .accessibilityHint("Press the button, or hold Space and release it to stop")
    }

    private var statusTitle: String {
        switch speech.phase {
        case .idle: "Hold Space to speak"
        case .requestingPermission: "Checking local speech access…"
        case .listening: "Listening…"
        case .processing: "Recognizing…"
        case .guess: "Confirm the best match"
        case .unavailable: "Speech setup needed"
        }
    }

    private var statusDetail: String {
        if case .unavailable(let message) = speech.phase { return message }
        return "Hold Space while speaking · Release to look up · Return confirms"
    }

    private var holdControlTitle: String {
        switch speech.phase {
        case .requestingPermission: isSpaceHeld ? "Keep holding Space…" : "Cancel recording"
        case .listening: isSpaceHeld ? "Release Space to finish" : "Stop recording"
        case .processing: "Record again"
        case .idle, .guess, .unavailable: "Hold Space to record"
        }
    }

    private var addButtonTitle: String {
        state.selectedEntry?.kind == .phrase ? "Add phrase  Return" : "Add word  Return"
    }

    private var isRecordingRequested: Bool {
        isSpaceHeld || isManualRecording
    }

    private func installSpaceMonitor() {
        guard spaceMonitor == nil else { return }
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            else { return event }

            if event.type == .keyDown {
                if !event.isARepeat { setSpaceHeld(true) }
            } else {
                setSpaceHeld(false)
            }
            return nil
        }
    }

    private func removeSpaceMonitor() {
        if let spaceMonitor { NSEvent.removeMonitor(spaceMonitor) }
        spaceMonitor = nil
        releaseRecordingHolds()
    }

    private func releaseRecordingHolds() {
        let wasRecording = isRecordingRequested
        isSpaceHeld = false
        isManualRecording = false
        if wasRecording { speech.stop() }
    }

    private func setSpaceHeld(_ held: Bool) {
        guard isSpaceHeld != held else { return }
        let wasRecording = isRecordingRequested
        isSpaceHeld = held
        recordingRequestChanged(wasRecording: wasRecording)
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
        guard !isSpaceHeld else { return }
        let wasRecording = isRecordingRequested
        isManualRecording.toggle()
        recordingRequestChanged(wasRecording: wasRecording)
    }

    private func confirm() {
        guard !speech.transcription.isEmpty, state.selectedEntry != nil else { return }
        state.confirmSpokenEntry()
        speech.reset()
    }
}

private extension SpeechRecognizer.Phase {
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}
