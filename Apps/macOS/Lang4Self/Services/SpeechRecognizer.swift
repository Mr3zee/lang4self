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
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    var isListening: Bool { phase == .listening }

    func start() {
        guard phase != .requestingPermission, phase != .listening else { return }
        if isUITesting {
            transcription = "Haus"
            confidence = 1
            phase = .listening
            return
        }
        let generation = UUID()
        startGeneration = generation
        Task {
            phase = .requestingPermission
            guard await permissionsGranted() else {
                guard startGeneration == generation else { return }
                phase = .unavailable("Microphone and Speech Recognition access are required. Enable both in System Settings → Privacy & Security.")
                return
            }
            guard startGeneration == generation else { return }
            beginRecognition()
        }
    }

    func rerecord() {
        cancel()
        start()
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
