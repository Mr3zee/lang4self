import AppKit
import SwiftUI
import Lang4SelfCore

struct DictionaryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var speech: SpeechRecognizer
    @EnvironmentObject private var voiceSearchShortcut: VoiceSearchShortcutController
    @EnvironmentObject private var germanSpeech: GermanSpeechController
    @State private var isManualRecording = false
    @State private var isShowingAddedListSelection = false
    @FocusState private var focusedControl: FocusControl?
    let automaticallyFocusContent: Bool

    private enum FocusControl: Hashable { case search, record, results }

    var body: some View {
        VStack(spacing: 0) {
            speechSearch

            Divider()

            textSearch

            Divider()

            lookupResults
        }
        .navigationTitle("Dictionary")
        .onKeyPress(.space, phases: .all, action: handleSpaceKeyPress)
        .onChange(of: focusedControl) { _, control in
            voiceSearchShortcut.dictionaryTextSearchFocusChanged(isFocused: control == .search)
        }
        .onChange(of: state.searchQuery) { _, query in
            let isVoiceResult = !speech.transcription.isEmpty && query == speech.transcription
            if !isVoiceResult, focusedControl == .search, speech.phase != .idle {
                releaseRecordingHolds()
                speech.reset()
                isShowingAddedListSelection = false
            }
            state.search(query, immediate: isVoiceResult, selectFirstResult: isVoiceResult)
        }
        .onChange(of: speech.transcription) { _, transcription in
            guard !transcription.isEmpty, state.searchQuery != transcription else { return }
            state.searchQuery = transcription
        }
        .onChange(of: speech.phase) { _, phase in
            if phase == .listening, !isRecordingRequested {
                speech.stop()
            }
            if phase == .listening, speech.transcription.isEmpty {
                state.search("")
            }
            if phase != .listening, phase != .requestingPermission {
                isManualRecording = false
            }
            if phase == .guess {
                focusResults()
            } else if (phase == .idle || phase.isUnavailable), !isRecordingRequested {
                isShowingAddedListSelection = false
                if focusedControl != .search {
                    DispatchQueue.main.async { focusedControl = .record }
                }
            }
        }
        .onChange(of: state.searchResults.map(\.id)) { _, _ in
            if speech.phase == .guess, !state.isSearchingDictionary { focusResults() }
        }
        .onChange(of: state.isSearchingDictionary) { _, isSearching in
            guard speech.phase == .guess else { return }
            if isSearching {
                focusedControl = nil
            } else {
                focusResults()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusDictionarySearch)) { _ in
            state.route = .dictionary
            focusedControl = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusDictionaryContent)) { _ in
            if state.searchResults.isEmpty {
                focusedControl = .search
            } else {
                focusFirstResult()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            releaseRecordingHolds()
        }
        .onAppear {
            voiceSearchShortcut.startMonitoring()
            if !speech.transcription.isEmpty {
                state.search(speech.transcription, immediate: true, selectFirstResult: true)
            }
            updateGermanSpeechTarget()
            guard automaticallyFocusContent else { return }
            DispatchQueue.main.async { focusedControl = .record }
        }
        .onDisappear {
            voiceSearchShortcut.dictionaryTextSearchFocusChanged(isFocused: false)
            releaseRecordingHolds()
            speech.reset()
            germanSpeech.setTarget(nil, in: .dictionary)
        }
        .onChange(of: displayedGermanForSpeech) { _, _ in updateGermanSpeechTarget() }
    }

    private var displayedGermanForSpeech: String? {
        if !state.isSearchingDictionary,
           !state.searchQuery.isEmpty,
           !state.searchResults.isEmpty,
           let selectedEntry = state.selectedEntry {
            return selectedEntry.german
        }
        return speech.transcription.isEmpty ? nil : speech.transcription
    }

    private func updateGermanSpeechTarget() {
        germanSpeech.setTarget(displayedGermanForSpeech, in: .dictionary)
    }

    private var textSearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Text search")
                    .font(.headline)
                Spacer()
                KeyboardShortcutHint(.commandF)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("German, English, or Russian", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($focusedControl, equals: .search)
                    .accessibilityIdentifier("dictionary.search")
                    .onSubmit(focusFirstResult)
                    .onKeyPress(.downArrow) {
                        focusFirstResult()
                        return state.searchResults.isEmpty ? .ignored : .handled
                    }
                    .onExitCommand(perform: leaveTextSearch)
                if !state.searchQuery.isEmpty {
                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("dictionary.clear-search")
                }
            }
            .padding(9)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(12)
    }

    private var speechSearch: some View {
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
                .accessibilityIdentifier("dictionary.voice-status")

            Group {
                if !speech.transcription.isEmpty {
                    VStack(spacing: 7) {
                        Text(GermanTextPresentation.hyphenated(speech.transcription))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 520)
                            .textSelection(.enabled)
                            .accessibilityLabel(speech.transcription)
                            .accessibilityIdentifier("dictionary.voice-transcription")
                        if speech.hasMultipleAlternatives, let position = speech.alternativePosition {
                            HStack(spacing: 10) {
                                Button { cycleVoiceAlternative(by: -1) } label: {
                                    Image(systemName: "arrow.left")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Previous recognition result")
                                Text("\(position) · \(confidencePercent)% confidence")
                                    .monospacedDigit()
                                    .accessibilityIdentifier("dictionary.voice-confidence")
                                Button { cycleVoiceAlternative(by: 1) } label: {
                                    Image(systemName: "arrow.right")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Next recognition result")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("\(confidencePercent)% confidence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .accessibilityIdentifier("dictionary.voice-confidence")
                        }
                    }
                } else {
                    statusDetail
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
            }
            .frame(minHeight: 64)

            speechControls
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background {
            SpeechAuroraBackground()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var lookupResults: some View {
        if state.searchQuery.isEmpty {
            PlaceholderView(
                symbol: "waveform.and.magnifyingglass",
                title: "Say or type a word or phrase",
                detail: "Voice recognition and lookup stay on this Mac. Nothing is uploaded."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.isSearchingDictionary {
            VStack(spacing: 12) {
                ProgressView()
                Text(searchActivityTitle)
                    .foregroundStyle(.secondary)
                if state.dictionaryTranslationPhase == .downloadingLanguages {
                    Text("Search will continue automatically when Apple’s language files are ready.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(
                state.dictionaryTranslationPhase == .downloadingLanguages
                    ? "dictionary.translation-download"
                    : "dictionary.searching"
            )
        } else if let entry = state.selectedEntry, !state.searchResults.isEmpty {
            HSplitView {
                List(state.searchResults, selection: $state.selectedEntry) { result in
                    EntryRow(entry: result)
                        .tag(result)
                        .contextMenu {
                            Button(contextAddLabel) { state.addToPersonalDictionary(result) }
                        }
                }
                .frame(minWidth: 260, idealWidth: 310)
                .focused($focusedControl, equals: .results)
                .accessibilityIdentifier("dictionary.results")
                .onKeyPress(.return) {
                    guard let selectedEntry = state.selectedEntry,
                          state.addedListID(for: selectedEntry) == nil
                    else {
                        return .ignored
                    }
                    state.addToPersonalDictionary(selectedEntry)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    guard isVoiceResult,
                          state.addedListID(for: entry) != nil
                    else {
                        return .ignored
                    }
                    isShowingAddedListSelection = true
                    return .handled
                }

                entryDetail(entry)
            }
        } else {
            PlaceholderView(
                symbol: "questionmark.folder",
                title: "No match",
                detail: "Try another spelling or import the complete dict.cc file in Settings."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchActivityTitle: String {
        switch state.dictionaryTranslationPhase {
        case .idle: "Searching…"
        case .checkingAvailability: "Checking Apple Translation…"
        case .downloadingLanguages: "Downloading German–English translation…"
        case .translating: "Translating on this Mac…"
        }
    }

    @ViewBuilder
    private var speechControls: some View {
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
        .buttonStyle(SpeechActionButtonStyle(isListening: false))
        .controlSize(.large)
        .disabled(speech.phase == .requestingPermission || voiceSearchShortcut.isSpaceHeld)
        .focusable()
        .focused($focusedControl, equals: .record)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            DispatchQueue.main.async { speech.requestPermissions() }
            return .handled
        }
        .accessibilityIdentifier("dictionary.voice-permission")
        .accessibilityLabel("Request speech access")
        .accessibilityHint("Allow microphone and Speech Recognition access without starting a recording")
    }

    @ViewBuilder
    private func entryDetail(_ entry: DictionaryEntry) -> some View {
        if isVoiceResult {
            EntryDetailView(
                entry: entry,
                addLabel: addButtonTitle,
                addShortcut: .returnKey,
                addShortcutModifiers: [],
                addAccessibilityIdentifier: "dictionary.add-selected",
                wordLists: state.wordLists,
                addedListID: state.addedListID(for: entry),
                isShowingListSelection: $isShowingAddedListSelection,
                switchAddedListAction: { await state.switchListForAddedEntry(entry, to: $0) },
                createAndSwitchAddedListAction: { await state.createListForAddedEntry(entry, named: $0) },
                didFinishListSelection: focusResults,
                addAction: { state.addToPersonalDictionary(entry) }
            )
        } else {
            EntryDetailView(
                entry: entry,
                addLabel: addButtonTitle,
                wordLists: state.wordLists,
                addedListID: state.addedListID(for: entry),
                switchAddedListAction: { await state.switchListForAddedEntry(entry, to: $0) },
                createAndSwitchAddedListAction: { await state.createListForAddedEntry(entry, named: $0) },
                addAction: { state.addToPersonalDictionary(entry) }
            )
        }
    }

    private var holdToRecordControl: some View {
        Button(action: toggleManualRecording) {
            Label(holdControlTitle, systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                .fontWeight(.semibold)
                .frame(width: 180)
        }
        .buttonStyle(SpeechActionButtonStyle(isListening: speech.isListening))
        .controlSize(.large)
        .focusable()
        .focused($focusedControl, equals: .record)
        .focusEffectDisabled()
        .overlay {
            Capsule()
                .strokeBorder(
                    focusedControl == .record && !voiceSearchShortcut.isSpaceHeld
                        ? Color(nsColor: .keyboardFocusIndicatorColor)
                        : .clear,
                    lineWidth: 3
                )
                .padding(2)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("dictionary.voice-search")
        .accessibilityLabel(speech.isListening ? "Stop recording" : "Start recording")
        .accessibilityHint("Press the button, or hold Space outside a text field and release it to stop")
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
            Text("Click record, or hold Space when you are not typing · Release to look up")
        }
    }

    private var holdControlTitle: String {
        switch speech.phase {
        case .requestingPermission: voiceSearchShortcut.isSpaceHeld ? "Keep holding Space…" : "Cancel recording"
        case .listening: voiceSearchShortcut.isSpaceHeld ? "Release Space to finish" : "Stop recording"
        case .processing: "Record again"
        case .idle, .guess, .unavailable: "Hold Space to record"
        }
    }

    private var addButtonTitle: String {
        state.selectedEntry?.kind == .phrase ? "Add phrase" : "Add word"
    }

    private var confidencePercent: Int {
        Int((min(max(speech.confidence, 0), 1) * 100).rounded())
    }

    private func cycleVoiceAlternative(by offset: Int) {
        isShowingAddedListSelection = false
        speech.selectAlternative(by: offset)
    }

    private var contextAddLabel: String {
        "Add to \(state.selectedWordList?.name ?? "My words")"
    }

    private var isVoiceResult: Bool {
        speech.phase == .guess
            && !speech.transcription.isEmpty
            && state.searchQuery == speech.transcription
    }

    private var isRecordingRequested: Bool {
        voiceSearchShortcut.isSpaceHeld || isManualRecording
    }

    private func clearSearch() {
        releaseRecordingHolds()
        speech.reset()
        state.search("")
        focusedControl = .search
    }

    private func leaveTextSearch() {
        releaseRecordingHolds()
        speech.reset()
        state.search("")
        focusedControl = .record
    }

    private func focusFirstResult() {
        guard let first = state.searchResults.first else { return }
        state.selectedEntry = first
        focusedControl = .results
    }

    private func focusResults() {
        guard !state.searchResults.isEmpty else { return }
        DispatchQueue.main.async { focusedControl = .results }
    }

    private func releaseRecordingHolds() {
        let wasRecording = isRecordingRequested
        voiceSearchShortcut.cancelSpaceHold()
        isManualRecording = false
        if wasRecording { speech.stop() }
    }

    private func handleSpaceKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard focusedControl != .search else { return .ignored }
        if keyPress.phase == .down {
            voiceSearchShortcut.beginDictionarySpaceHold()
        } else if keyPress.phase == .up {
            voiceSearchShortcut.releaseSpaceHold()
        }
        return .handled
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
        guard speech.hasRecordingPermission, !voiceSearchShortcut.isSpaceHeld else { return }
        let wasRecording = isRecordingRequested
        isManualRecording.toggle()
        recordingRequestChanged(wasRecording: wasRecording)
    }
}

struct SpeechAuroraMotion {
    static func phase(at date: Date, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
    }

    static func offset(
        at phase: TimeInterval,
        period: TimeInterval,
        xAmplitude: CGFloat,
        yAmplitude: CGFloat,
        initialAngle: Double
    ) -> CGSize {
        let progress = phase.truncatingRemainder(dividingBy: period) / period
        let angle = progress * 2 * Double.pi + initialAngle
        return CGSize(
            width: cos(angle) * xAmplitude,
            height: sin(angle) * yAmplitude
        )
    }
}

private struct SpeechAuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0, paused: reduceMotion)) { timeline in
            GeometryReader { geometry in
                let phase = SpeechAuroraMotion.phase(at: timeline.date, reduceMotion: reduceMotion)
                let size = geometry.size

                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Color.black.opacity(colorScheme == .dark ? 0.20 : 0.055)

                    auroraBlob(
                        color: Gender.masculine.color,
                        size: CGSize(width: max(size.width * 0.34, 250), height: max(size.height * 0.92, 220)),
                        position: CGPoint(x: size.width * -0.01, y: size.height * 0.24),
                        phase: phase,
                        period: 31,
                        amplitude: CGSize(width: 18, height: 11),
                        initialAngle: 0.3,
                        rotation: -16
                    )

                    auroraBlob(
                        color: Gender.feminine.color,
                        size: CGSize(width: max(size.width * 0.31, 235), height: max(size.height * 0.84, 205)),
                        position: CGPoint(x: size.width * 1.02, y: size.height * 0.22),
                        phase: phase,
                        period: 37,
                        amplitude: CGSize(width: 15, height: 13),
                        initialAngle: 2.1,
                        rotation: 19
                    )

                    auroraBlob(
                        color: Gender.plural.color,
                        size: CGSize(width: max(size.width * 0.29, 220), height: max(size.height * 0.70, 180)),
                        position: CGPoint(x: size.width * 0.18, y: size.height * 1.04),
                        phase: phase,
                        period: 41,
                        amplitude: CGSize(width: 20, height: 9),
                        initialAngle: 3.7,
                        rotation: 11
                    )

                    auroraBlob(
                        color: Gender.neuter.color,
                        size: CGSize(width: max(size.width * 0.27, 210), height: max(size.height * 0.66, 170)),
                        position: CGPoint(x: size.width * 0.82, y: size.height * 1.06),
                        phase: phase,
                        period: 43,
                        amplitude: CGSize(width: 17, height: 10),
                        initialAngle: 5.2,
                        rotation: -12
                    )

                    RadialGradient(
                        colors: [.clear, .black.opacity(colorScheme == .dark ? 0.12 : 0.035)],
                        center: .center,
                        startRadius: min(size.width, size.height) * 0.30,
                        endRadius: max(size.width, size.height) * 0.68
                    )

                    LinearGradient(
                        colors: [.white.opacity(colorScheme == .dark ? 0.025 : 0.10), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .clipped()
            }
        }
    }

    private func auroraBlob(
        color: Color,
        size: CGSize,
        position: CGPoint,
        phase: TimeInterval,
        period: TimeInterval,
        amplitude: CGSize,
        initialAngle: Double,
        rotation: Double
    ) -> some View {
        let offset = SpeechAuroraMotion.offset(
            at: phase,
            period: period,
            xAmplitude: amplitude.width,
            yAmplitude: amplitude.height,
            initialAngle: initialAngle
        )
        let intensity = colorScheme == .dark ? 0.14 : 0.09

        return ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(intensity), color.opacity(intensity * 0.30), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(size.width, size.height) * 0.48
                    )
                )

            Ellipse()
                .fill(color.opacity(intensity * 0.32))
                .frame(width: size.width * 0.46, height: size.height * 0.72)
                .offset(x: size.width * 0.20, y: size.height * -0.08)
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .blur(radius: 32)
        .rotationEffect(.degrees(rotation))
        .position(x: position.x + offset.width, y: position.y + offset.height)
    }
}

private struct SpeechActionButtonStyle: ButtonStyle {
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

extension Notification.Name {
    static let focusDictionarySearch = Notification.Name("focusDictionarySearch")
    static let focusDictionaryContent = Notification.Name("focusDictionaryContent")
}
