import AppKit
import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
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

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private var recognitionFinished = false
    private var startGeneration = UUID()
    private var recognitionGeneration = UUID()
    private let isUITesting: Bool
    private var simulatesUndeterminedPermissions: Bool

    var isListening: Bool { phase == .listening }
    var hasRecordingPermission: Bool {
        if isUITesting { return !simulatesUndeterminedPermissions }
        return SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    init(isUITesting: Bool, simulatesUndeterminedPermissions: Bool) {
        self.isUITesting = isUITesting
        self.simulatesUndeterminedPermissions = simulatesUndeterminedPermissions
        super.init()
    }

    func start() {
        // Permission setup is a separate user action. Starting a recording must
        // never display permission prompts or continue into setup implicitly.
        guard hasRecordingPermission else { return }
        guard phase != .requestingPermission, phase != .listening else { return }
        if isUITesting {
            transcription = "Der Hund"
            confidence = 1
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
            phase = .guess
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
        transcription = ""
        confidence = 0
        phase = .idle
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
        transcription = ""
        confidence = 0
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
                    self.transcription = result.bestTranscription.formattedString
                    self.confidence = result.bestTranscription.segments.last?.confidence ?? 0
                    if result.isFinal {
                        self.recognitionFinished = true
                        if self.phase == .processing { self.completeRecognition() }
                    }
                }
                if let error {
                    self.recognitionFinished = true
                    if self.phase == .processing {
                        self.completeRecognition(error: error)
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

    private func completeRecognition(error: Error? = nil) {
        request = nil
        task = nil
        if transcription.isEmpty, let error {
            phase = .unavailable(error.localizedDescription)
        } else {
            phase = transcription.isEmpty ? .idle : .guess
        }
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
    func start()
    func rerecord()
    func stop()
}

extension SpeechRecognizer: VoiceSearchShortcutRecording {}

@MainActor
protocol VoiceSearchShortcutContext: AnyObject {
    var hasActiveDialog: Bool { get }
    var hasEditableTextInputFocus: Bool { get }
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

    var hasEditableTextInputFocus: Bool {
        guard let editor = application.keyWindow?.firstResponder as? NSTextView else { return false }
        return editor.isEditable
    }
}

@MainActor
final class VoiceSearchShortcutController: ObservableObject {
    @Published private(set) var isSpaceHeld = false

    private let router: any VoiceSearchShortcutRouting
    private let speech: any VoiceSearchShortcutRecording
    private let context: any VoiceSearchShortcutContext
    private let holdDelay: TimeInterval
    private let onForwardedSpaceEvent: () -> Void
    private var eventMonitor: Any?
    private var isSpaceDown = false
    private var pendingHold: UUID?
    private var isDictionaryTextSearchFocused = false

    init(
        router: any VoiceSearchShortcutRouting,
        speech: any VoiceSearchShortcutRecording,
        context: any VoiceSearchShortcutContext,
        holdDelay: TimeInterval,
        onForwardedSpaceEvent: @escaping () -> Void
    ) {
        self.router = router
        self.speech = speech
        self.context = context
        self.holdDelay = holdDelay
        self.onForwardedSpaceEvent = onForwardedSpaceEvent
    }

    func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            let forwardedEvent = self.handle(event)
            if event.keyCode == 49, forwardedEvent != nil {
                self.onForwardedSpaceEvent()
            }
            return forwardedEvent
        }
    }

    func stopMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        cancelSpaceHold()
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
        pendingHold = nil
        guard isSpaceHeld else { return }
        isSpaceHeld = false
        speech.stop()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 49 else { return event }

        // Finish or consume a gesture that already began even if a sheet appeared
        // or modifiers changed while Space was down. Otherwise repeats escape to
        // the new responder and macOS emits its invalid-action beep.
        if isSpaceDown {
            if event.type == .keyDown { return nil }
            pendingHold = nil
            if isSpaceHeld {
                releaseSpaceHold()
                return nil
            }
            isSpaceDown = false
            return event
        }

        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              !context.hasActiveDialog
        else { return event }

        // An editable text field always owns Space, including a long press and
        // its repeat events. Voice search remains available from the button.
        guard !textInputOwnsSpace else { return event }
        guard !event.isARepeat else { return nil }
        isSpaceDown = true

        if router.route != .review {
            beginSpaceHold()
            return nil
        }

        scheduleSpaceHold()
        return event
    }

    private var textInputOwnsSpace: Bool {
        if router.route == .dictionary {
            return isDictionaryTextSearchFocused
        }
        return context.hasEditableTextInputFocus
    }

    private func scheduleSpaceHold() {
        let pending = UUID()
        pendingHold = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay) { [weak self] in
            guard let self,
                  self.pendingHold == pending,
                  self.isSpaceDown
            else { return }
            self.beginSpaceHold()
        }
    }

    private func beginSpaceHold() {
        pendingHold = nil
        guard isSpaceDown, !isSpaceHeld else { return }
        isSpaceHeld = true
        router.route = .dictionary

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
