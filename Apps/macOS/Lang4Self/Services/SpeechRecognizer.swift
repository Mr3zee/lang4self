import AppKit
import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
    struct Alternative: Identifiable, Equatable {
        var id: String { transcription.folding(options: [.caseInsensitive], locale: .current) }
        let transcription: String
        let confidence: Float
    }

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case listening
        case processing
        case guess
        case unavailable(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcription = ""
    @Published private(set) var confidence: Float = 0
    @Published private(set) var alternatives: [Alternative] = []
    @Published private(set) var selectedAlternativeIndex = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private var recognitionFinished = false
    private var startGeneration = UUID()
    private var recognitionGeneration = UUID()
    private let isUITesting: Bool
    private let uiTestingAlternativeCount: Int
    private var simulatesUndeterminedPermissions: Bool

    var isListening: Bool { phase == .listening }
    var hasMultipleAlternatives: Bool { alternatives.count > 1 }
    var alternativePosition: String? {
        guard !alternatives.isEmpty else { return nil }
        return "\(selectedAlternativeIndex + 1) of \(alternatives.count)"
    }
    var hasRecordingPermission: Bool {
        if isUITesting { return !simulatesUndeterminedPermissions }
        return SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    init(
        isUITesting: Bool,
        simulatesUndeterminedPermissions: Bool,
        uiTestingAlternativeCount: Int
    ) {
        self.isUITesting = isUITesting
        self.simulatesUndeterminedPermissions = simulatesUndeterminedPermissions
        self.uiTestingAlternativeCount = uiTestingAlternativeCount
        super.init()
    }

    func start() {
        // Permission setup is a separate user action. Starting a recording must
        // never display permission prompts or continue into setup implicitly.
        guard hasRecordingPermission else { return }
        guard phase != .requestingPermission, phase != .listening else { return }
        if isUITesting {
            setAlternatives([
                .init(transcription: "Die Hunde", confidence: 0.78),
                .init(transcription: "Der Hund", confidence: 0.96),
                .init(transcription: "Ein Hund", confidence: 0.61)
            ], limit: uiTestingAlternativeCount)
            phase = .listening
            return
        }
        beginRecognition()
    }

    func rerecord() {
        cancel()
        start()
    }

    func requestPermissions() {
        guard phase != .requestingPermission else { return }
        if isUITesting {
            phase = .requestingPermission
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                simulatesUndeterminedPermissions = false
                phase = .idle
            }
            return
        }
        let generation = UUID()
        startGeneration = generation
        Task {
            phase = .requestingPermission
            let granted = await permissionsGranted()
            guard startGeneration == generation else { return }
            phase = granted
                ? .idle
                : .unavailable("Microphone and Speech Recognition access are required. Enable both in System Settings → Privacy & Security.")
        }
    }

    func stop() {
        if isUITesting, phase == .listening {
            phase = completedRecognitionPhase
            return
        }
        if phase == .requestingPermission {
            startGeneration = UUID()
            phase = .idle
            return
        }
        finishListening()
    }

    func reset() {
        cancel()
        clearAlternatives()
        phase = .idle
    }

    func selectAlternative(by offset: Int) {
        guard alternatives.count > 1 else { return }
        let count = alternatives.count
        selectedAlternativeIndex = ((selectedAlternativeIndex + offset) % count + count) % count
        applySelectedAlternative()
    }

    private func permissionsGranted() async -> Bool {
        let speechAllowed: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else { return false }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    private func beginRecognition() {
        cancelAudioOnly()
        clearAlternatives()
        recognitionFinished = false

        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            phase = .unavailable("German on-device dictation is not available yet. Install German Dictation in System Settings → Keyboard → Dictation Languages.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        self.request = request
        let generation = UUID()
        recognitionGeneration = generation

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .unavailable("No microphone input is available.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        hasInputTap = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.recognitionGeneration == generation else { return }
                if let result {
                    self.setAlternatives(Self.alternatives(from: result))
                    if result.isFinal {
                        self.recognitionFinished = true
                        if self.phase == .processing { self.completeRecognition() }
                    }
                }
                if let error {
                    self.recognitionFinished = true
                    if self.phase == .processing {
                        self.completeRecognition()
                    } else if self.transcription.isEmpty {
                        self.cancelAudioOnly()
                        self.phase = .unavailable(error.localizedDescription)
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            phase = .listening
        } catch {
            cancelAudioOnly()
            phase = .unavailable(error.localizedDescription)
        }
    }

    private func finishListening() {
        guard phase == .listening else { return }
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        if recognitionFinished {
            completeRecognition()
        } else {
            phase = .processing
        }
    }

    private func completeRecognition() {
        request = nil
        task = nil
        phase = completedRecognitionPhase
    }

    private var completedRecognitionPhase: Phase {
        transcription.isEmpty ? .idle : .guess
    }

    private func cancel() {
        startGeneration = UUID()
        cancelAudioOnly()
        phase = .idle
    }

    private func cancelAudioOnly() {
        recognitionFinished = false
        recognitionGeneration = UUID()
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func setAlternatives(_ newAlternatives: [Alternative], limit: Int = 5) {
        let previousTranscription = transcription
        alternatives = Array(
            newAlternatives.enumerated()
                .sorted { left, right in
                    if left.element.confidence == right.element.confidence {
                        return left.offset < right.offset
                    }
                    return left.element.confidence > right.element.confidence
                }
                .prefix(limit)
                .map(\.element)
        )
        selectedAlternativeIndex = alternatives.firstIndex {
            $0.transcription.compare(previousTranscription, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } ?? 0
        applySelectedAlternative()
    }

    private func applySelectedAlternative() {
        guard alternatives.indices.contains(selectedAlternativeIndex) else {
            transcription = ""
            confidence = 0
            return
        }
        let alternative = alternatives[selectedAlternativeIndex]
        transcription = alternative.transcription
        confidence = alternative.confidence
    }

    private func clearAlternatives() {
        alternatives = []
        selectedAlternativeIndex = 0
        transcription = ""
        confidence = 0
    }

    private static func alternatives(from result: SFSpeechRecognitionResult) -> [Alternative] {
        var seen = Set<String>()
        return result.transcriptions.compactMap { transcription in
            let text = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !text.isEmpty, seen.insert(key).inserted else { return nil }
            let confidence: Float
            if transcription.segments.isEmpty {
                confidence = 0
            } else {
                confidence = transcription.segments.reduce(0) { $0 + $1.confidence }
                    / Float(transcription.segments.count)
            }
            return Alternative(transcription: text, confidence: confidence)
        }
    }
}

@MainActor
protocol VoiceSearchShortcutRouting: AnyObject {
    var route: AppRoute { get set }
}

extension AppState: VoiceSearchShortcutRouting {}

@MainActor
protocol VoiceSearchShortcutRecording: AnyObject {
    var phase: SpeechRecognizer.Phase { get }
    var hasRecordingPermission: Bool { get }
    var hasMultipleAlternatives: Bool { get }
    func start()
    func rerecord()
    func stop()
    func selectAlternative(by offset: Int)
}

extension SpeechRecognizer: VoiceSearchShortcutRecording {}

@MainActor
protocol VoiceSearchShortcutContext: AnyObject {
    var hasActiveDialog: Bool { get }
}

@MainActor
final class AppKitVoiceSearchShortcutContext: VoiceSearchShortcutContext {
    private let application: NSApplication

    init(application: NSApplication) {
        self.application = application
    }

    var hasActiveDialog: Bool {
        application.modalWindow != nil
            || application.keyWindow?.sheetParent != nil
            || application.mainWindow?.attachedSheet != nil
    }

}

@MainActor
final class VoiceSearchShortcutController: ObservableObject {
    @Published private(set) var isSpaceHeld = false

    private let router: any VoiceSearchShortcutRouting
    private let speech: any VoiceSearchShortcutRecording
    private let context: any VoiceSearchShortcutContext
    private var isSpaceDown = false
    private var isDictionaryTextSearchFocused = false

    init(
        router: any VoiceSearchShortcutRouting,
        speech: any VoiceSearchShortcutRecording,
        context: any VoiceSearchShortcutContext
    ) {
        self.router = router
        self.speech = speech
        self.context = context
    }

    func releaseSpaceHold() {
        endSpaceHold()
    }

    func beginDictionarySpaceHold() {
        guard !isSpaceDown,
              !isDictionaryTextSearchFocused,
              !context.hasActiveDialog
        else { return }
        isSpaceDown = true
        beginSpaceHold()
    }

    func cancelSpaceHold() {
        endSpaceHold()
    }

    func dictionaryTextSearchFocusChanged(isFocused: Bool) {
        isDictionaryTextSearchFocused = isFocused
    }

    private func endSpaceHold() {
        isSpaceDown = false
        guard isSpaceHeld else { return }
        isSpaceHeld = false
        speech.stop()
    }

    func cycleVoiceAlternative(by offset: Int) -> Bool {
        guard router.route == .dictionary,
              speech.phase == .guess,
              speech.hasMultipleAlternatives,
              !context.hasActiveDialog
        else { return false }
        speech.selectAlternative(by: offset)
        return true
    }

    private func beginSpaceHold() {
        guard isSpaceDown, !isSpaceHeld else { return }
        isSpaceHeld = true

        if !speech.hasRecordingPermission {
            // Space only opens Dictionary's permission information. The
            // microphone setup button owns permission prompts.
            return
        }

        switch speech.phase {
        case .idle, .unavailable:
            speech.start()
        case .processing, .guess:
            speech.rerecord()
        case .requestingPermission, .listening:
            break
        }
    }
}
