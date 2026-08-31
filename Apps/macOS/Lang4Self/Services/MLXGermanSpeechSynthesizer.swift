import Foundation
import HuggingFace
import MLXAudioCore
@preconcurrency import MLXAudioTTS

struct MLXGermanSpeechConfiguration {
    let repositoryID: String
    let revision: String
    let cacheDirectory: URL
    let voice: String
    let language: String
    let warmupText: String
    let streamingInterval: TimeInterval
}

@MainActor
protocol MLXGermanSpeechGenerating: AnyObject {
    var sampleRate: Int { get }

    func generateSamplesStream(
        text: String,
        voice: String,
        language: String,
        streamingInterval: TimeInterval
    ) -> AsyncThrowingStream<[Float], Error>
}

@MainActor
private final class MLXGermanSpeechGenerationModel: MLXGermanSpeechGenerating {
    private let model: any SpeechGenerationModel

    init(model: any SpeechGenerationModel) {
        self.model = model
    }

    var sampleRate: Int { model.sampleRate }

    func generateSamplesStream(
        text: String,
        voice: String,
        language: String,
        streamingInterval: TimeInterval
    ) -> AsyncThrowingStream<[Float], Error> {
        model.generateSamplesStream(
            text: text,
            voice: voice,
            refAudio: nil,
            refText: nil,
            language: language,
            streamingInterval: streamingInterval
        )
    }
}

@MainActor
protocol MLXGermanSpeechModelLoading {
    func isModelDownloaded() async -> Bool
    func downloadModel() async throws
    func loadModel() async throws -> any MLXGermanSpeechGenerating
}

struct HuggingFaceMLXGermanSpeechModelLoader: MLXGermanSpeechModelLoading {
    let repositoryID: String
    let revision: String
    let cacheDirectory: URL

    func isModelDownloaded() async -> Bool {
        guard let snapshot = try? expectedSnapshot() else { return false }
        return Self.isCompleteSnapshot(snapshot)
    }

    func downloadModel() async throws {
        let (repository, cache, expectedSnapshot) = try repositoryCacheAndSnapshot()
        guard !Self.isCompleteSnapshot(expectedSnapshot) else { return }
        let client = HubClient(cache: cache)
        let snapshot = try await client.downloadSnapshot(
            of: repository,
            kind: .model,
            revision: revision,
            matching: ["*.json", "*.txt", "*.safetensors"],
            maxConcurrentDownloads: 4
        )

        guard Self.isCompleteSnapshot(snapshot) else {
            throw MLXGermanSpeechModelError.incompleteSnapshot(snapshot)
        }
    }

    func loadModel() async throws -> any MLXGermanSpeechGenerating {
        let snapshot = try expectedSnapshot()
        guard Self.isCompleteSnapshot(snapshot) else {
            throw MLXGermanSpeechModelError.modelNotDownloaded
        }

        let model = try await TTS.loadModel(
            modelRepo: snapshot.path,
            modelType: "qwen3_tts"
        )
        return MLXGermanSpeechGenerationModel(model: model)
    }

    private func expectedSnapshot() throws -> URL {
        let (_, _, snapshot) = try repositoryCacheAndSnapshot()
        return snapshot
    }

    private func repositoryCacheAndSnapshot() throws -> (Repo.ID, HubCache, URL) {
        guard let repository = Repo.ID(rawValue: repositoryID) else {
            throw MLXGermanSpeechModelError.invalidRepositoryID(repositoryID)
        }
        let cache = HubCache(cacheDirectory: cacheDirectory)
        let snapshot = cache
            .snapshotsDirectory(repo: repository, kind: .model)
            .appendingPathComponent(revision, isDirectory: true)
        return (repository, cache, snapshot)
    }

    private static func isCompleteSnapshot(_ directory: URL) -> Bool {
        let requiredFiles = [
            "config.json",
            "merges.txt",
            "model.safetensors",
            "tokenizer_config.json",
            "vocab.json",
            "speech_tokenizer/config.json",
            "speech_tokenizer/model.safetensors"
        ]
        return requiredFiles.allSatisfy { relativePath in
            let url = directory.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0
        }
    }
}

enum MLXGermanSpeechModelError: LocalizedError {
    case invalidRepositoryID(String)
    case incompleteSnapshot(URL)
    case modelNotDownloaded

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let repositoryID):
            "Invalid speech model repository: \(repositoryID)"
        case .incompleteSnapshot(let directory):
            "The downloaded speech model is incomplete at \(directory.path)."
        case .modelNotDownloaded:
            "The speech model has not been downloaded."
        }
    }
}

@MainActor
protocol MLXGermanSpeechAudioPlaying: AnyObject {
    func startStreaming(sampleRate: Double)
    func scheduleAudioChunk(_ samples: [Float], withCrossfade: Bool)
    func finishStreamingInput()
    func stop()
}

extension AudioPlayer: MLXGermanSpeechAudioPlaying {}

@MainActor
final class MLXGermanSpeechSynthesizer: GermanSpeechSynthesizing, GermanSpeechModelManaging {
    private struct PreparedSpeech {
        let text: String
        let samples: [Float]
        let sampleRate: Double
    }

    private let configuration: MLXGermanSpeechConfiguration
    private let modelLoader: any MLXGermanSpeechModelLoading
    private let fallback: any GermanSpeechSynthesizing
    private let player: any MLXGermanSpeechAudioPlaying

    private var model: (any MLXGermanSpeechGenerating)?
    private var warmupTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var requestedPreparationText: String?
    private var requestedSpeechText: String?
    private var preparationRequestID = 0
    private var speechRequestID = 0
    private var preparedSpeech: PreparedSpeech?
    private var hasStarted = false

    private(set) var modelStatus: GermanSpeechModelStatus = .checking
    var modelStatusDidChange: ((GermanSpeechModelStatus) -> Void)?

    init(
        configuration: MLXGermanSpeechConfiguration,
        modelLoader: any MLXGermanSpeechModelLoading,
        fallback: any GermanSpeechSynthesizing,
        player: any MLXGermanSpeechAudioPlaying
    ) {
        precondition(!configuration.repositoryID.isEmpty)
        precondition(!configuration.revision.isEmpty)
        precondition(!configuration.voice.isEmpty)
        precondition(!configuration.language.isEmpty)
        precondition(!configuration.warmupText.isEmpty)
        precondition(configuration.streamingInterval > 0)
        self.configuration = configuration
        self.modelLoader = modelLoader
        self.fallback = fallback
        self.player = player
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        fallback.start()

        warmupTask = Task { [weak self] in
            await self?.loadAndWarmModel(downloadIfNeeded: false)
        }
    }

    func downloadModel() {
        start()
        guard modelStatus != .downloading,
              modelStatus != .loading,
              modelStatus != .warming,
              modelStatus != .ready
        else { return }

        warmupTask?.cancel()
        warmupTask = Task { [weak self] in
            await self?.loadAndWarmModel(downloadIfNeeded: true)
        }
    }

    func prepare(_ text: String?) {
        start()

        if let text, requestedSpeechText == text {
            return
        }

        let supersededSpeechTask = speechTask
        supersededSpeechTask?.cancel()
        speechTask = nil
        requestedSpeechText = nil
        speechRequestID &+= 1
        if supersededSpeechTask != nil {
            player.stop()
        }

        let supersededPreparationTask = preparationTask
        supersededPreparationTask?.cancel()
        preparationTask = nil
        requestedPreparationText = text
        preparationRequestID &+= 1
        let requestID = preparationRequestID

        guard let text else {
            preparedSpeech = nil
            return
        }
        guard preparedSpeech?.text != text else { return }
        preparedSpeech = nil

        preparationTask = Task { [weak self] in
            guard let self else { return }
            await supersededSpeechTask?.value
            await supersededPreparationTask?.value
            await warmupTask?.value
            guard !Task.isCancelled, let model else { return }

            do {
                let samples = try await generateSamples(
                    text: text,
                    model: model,
                    streamingInterval: 0.32
                )
                try Task.checkCancellation()
                guard preparationRequestID == requestID,
                      requestedPreparationText == text
                else { return }
                preparedSpeech = PreparedSpeech(
                    text: text,
                    samples: samples,
                    sampleRate: Double(model.sampleRate)
                )
            } catch is CancellationError {
                // A newer pronunciation target superseded this work.
            } catch {
                NSLog("Lang4Self could not prepare MLX pronunciation: %@", error.localizedDescription)
            }

            if preparationRequestID == requestID {
                preparationTask = nil
            }
        }
    }

    func speak(_ text: String) {
        start()

        let supersededSpeechTask = speechTask
        supersededSpeechTask?.cancel()
        if supersededSpeechTask != nil {
            player.stop()
        }

        let pendingPreparationTask = requestedPreparationText == text
            ? preparationTask
            : nil
        let supersededPreparationTask = preparationTask
        if pendingPreparationTask == nil {
            supersededPreparationTask?.cancel()
            preparationTask = nil
            requestedPreparationText = nil
            preparationRequestID &+= 1
        }

        requestedSpeechText = text
        speechRequestID &+= 1
        let requestID = speechRequestID
        speechTask = Task { [weak self] in
            guard let self else { return }
            await supersededSpeechTask?.value
            await supersededPreparationTask?.value
            await warmupTask?.value
            guard !Task.isCancelled,
                  speechRequestID == requestID,
                  requestedSpeechText == text
            else { return }

            if let preparedSpeech, preparedSpeech.text == text {
                play(preparedSpeech)
                return
            }

            guard let model else {
                requestedSpeechText = nil
                fallback.speak(text)
                return
            }

            fallback.stop()
            player.startStreaming(sampleRate: Double(model.sampleRate))

            do {
                var generatedSamples: [Float] = []
                let stream = model.generateSamplesStream(
                    text: text,
                    voice: configuration.voice,
                    language: configuration.language,
                    streamingInterval: configuration.streamingInterval
                )
                for try await samples in stream {
                    try Task.checkCancellation()
                    guard speechRequestID == requestID,
                          requestedSpeechText == text
                    else {
                        throw CancellationError()
                    }
                    generatedSamples.append(contentsOf: samples)
                    player.scheduleAudioChunk(samples, withCrossfade: false)
                }
                try Task.checkCancellation()
                guard speechRequestID == requestID,
                      requestedSpeechText == text
                else {
                    throw CancellationError()
                }
                player.finishStreamingInput()
                if !generatedSamples.isEmpty {
                    preparedSpeech = PreparedSpeech(
                        text: text,
                        samples: generatedSamples,
                        sampleRate: Double(model.sampleRate)
                    )
                }
            } catch is CancellationError {
                if speechRequestID == requestID {
                    requestedSpeechText = nil
                    player.stop()
                }
            } catch {
                guard speechRequestID == requestID else { return }
                requestedSpeechText = nil
                player.stop()
                fallback.speak(text)
                NSLog("Lang4Self could not stream MLX pronunciation: %@", error.localizedDescription)
            }
        }
    }

    func stop() {
        warmupTask?.cancel()
        warmupTask = nil
        preparationTask?.cancel()
        preparationTask = nil
        speechTask?.cancel()
        speechTask = nil
        requestedPreparationText = nil
        requestedSpeechText = nil
        preparationRequestID &+= 1
        speechRequestID &+= 1
        player.stop()
        fallback.stop()
    }

    private func play(_ preparedSpeech: PreparedSpeech) {
        fallback.stop()
        player.startStreaming(sampleRate: preparedSpeech.sampleRate)
        player.scheduleAudioChunk(preparedSpeech.samples, withCrossfade: false)
        player.finishStreamingInput()
    }

    private func loadAndWarmModel(downloadIfNeeded: Bool) async {
        do {
            let isDownloaded = await modelLoader.isModelDownloaded()
            try Task.checkCancellation()
            if !isDownloaded {
                guard downloadIfNeeded else {
                    updateModelStatus(.notDownloaded)
                    return
                }
                updateModelStatus(.downloading)
                try await modelLoader.downloadModel()
                try Task.checkCancellation()
            }

            updateModelStatus(.loading)
            let loadedModel = try await modelLoader.loadModel()
            try Task.checkCancellation()
            updateModelStatus(.warming)
            _ = try await generateSamples(
                text: configuration.warmupText,
                model: loadedModel,
                streamingInterval: configuration.streamingInterval
            )
            try Task.checkCancellation()
            model = loadedModel
            updateModelStatus(.ready)
        } catch is CancellationError {
            // Application termination cancels startup work.
        } catch {
            updateModelStatus(.failed(error.localizedDescription))
            NSLog("Lang4Self could not load the MLX speech model: %@", error.localizedDescription)
        }
    }

    private func updateModelStatus(_ status: GermanSpeechModelStatus) {
        guard modelStatus != status else { return }
        modelStatus = status
        modelStatusDidChange?(status)
    }

    private func generateSamples(
        text: String,
        model: any MLXGermanSpeechGenerating,
        streamingInterval: TimeInterval
    ) async throws -> [Float] {
        var samples: [Float] = []
        let stream = model.generateSamplesStream(
            text: text,
            voice: configuration.voice,
            language: configuration.language,
            streamingInterval: streamingInterval
        )
        for try await chunk in stream {
            try Task.checkCancellation()
            samples.append(contentsOf: chunk)
        }
        return samples
    }
}
