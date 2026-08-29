import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case listening
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
    private var silenceWorkItem: DispatchWorkItem?
    private var hasInputTap = false
    private var recognitionGeneration = UUID()

    var isListening: Bool { phase == .listening }

    func start() {
        Task {
            phase = .requestingPermission
            guard await permissionsGranted() else {
                phase = .unavailable("Microphone and Speech Recognition access are required. Enable both in System Settings → Privacy & Security.")
                return
            }
            beginRecognition()
        }
    }

    func rerecord() {
        cancel()
        start()
    }

    func acceptCurrentGuess() {
        guard !transcription.isEmpty else { return }
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
                    self.scheduleSilenceFinish()
                    if result.isFinal { self.finishListening() }
                } else if let error, self.transcription.isEmpty {
                    self.cancelAudioOnly()
                    self.phase = .unavailable(error.localizedDescription)
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

    private func scheduleSilenceFinish() {
        silenceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.finishListening() }
        }
        silenceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private func finishListening() {
        guard phase == .listening else { return }
        silenceWorkItem?.cancel()
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        phase = transcription.isEmpty ? .idle : .guess
    }

    private func cancel() {
        cancelAudioOnly()
        phase = .idle
    }

    private func cancelAudioOnly() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
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
