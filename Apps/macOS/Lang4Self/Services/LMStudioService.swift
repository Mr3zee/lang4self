import AppKit
import Foundation
import Lang4SelfCore

struct LMStudioModel: Decodable, Hashable, Identifiable {
    struct Quantization: Decodable, Hashable {
        let name: String
    }

    let type: String
    let modelKey: String
    let displayName: String
    let sizeBytes: Int64
    let paramsString: String?
    let quantization: Quantization?
    let maxContextLength: Int?

    var id: String { modelKey }

    var details: String {
        [paramsString, quantization?.name, ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

enum LMStudioGPUOffload: String, CaseIterable, Codable, Identifiable {
    case automatic
    case maximum
    case cpuOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .maximum: "Maximum (GPU)"
        case .cpuOnly: "CPU only"
        }
    }
}

struct LMStudioSettings: Codable, Equatable {
    var modelKey = ""
    var contextLength = 16_384
    var gpuOffload = LMStudioGPUOffload.maximum
    var temperature = 0.4
    var topP = 0.9
    var maxOutputTokens = 4_096

    static let defaults = LMStudioSettings()

    var sanitized: LMStudioSettings {
        var value = self
        value.contextLength = min(max(contextLength, 2_048), 262_144)
        value.temperature = min(max(temperature, 0), 2)
        value.topP = min(max(topP, 0.05), 1)
        value.maxOutputTokens = min(max(maxOutputTokens, 256), 16_384)
        return value
    }

    func requiresReload(comparedTo other: LMStudioSettings) -> Bool {
        modelKey != other.modelKey || contextLength != other.contextLength || gpuOffload != other.gpuOffload
    }
}

enum LMStudioProgress: Equatable {
    case idle
    case findingModel
    case launchingStudio
    case startingServer
    case loadingModel(String)
    case ready(String)
    case generating(Int, String)
    case unloading
    case failed(String)

    var message: String {
        switch self {
        case .idle: "LM Studio is idle"
        case .findingModel: "Finding the installed language model…"
        case .launchingStudio: "Starting LM Studio…"
        case .startingServer: "Starting the local LM Studio server…"
        case .loadingModel(let name): "Loading \(name)…"
        case .ready(let name): "\(name) is loaded"
        case .generating(let count, let name): "Generating \(count) sentence\(count == 1 ? "" : "s") with \(name)…"
        case .unloading: "Offloading the language model…"
        case .failed(let message): message
        }
    }

    var isWorking: Bool {
        switch self {
        case .findingModel, .launchingStudio, .startingServer, .loadingModel, .generating, .unloading: true
        default: false
        }
    }
}

enum LMStudioError: LocalizedError {
    case cliNotFound
    case noLanguageModel
    case selectedModelUnavailable(String)
    case commandTimedOut(String)
    case commandFailed(String)
    case serverUnavailable
    case api(Int, String)
    case invalidResponse(String)
    case noValidSentences

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "LM Studio's command-line tool was not found. Open LM Studio and install or update its CLI."
        case .noLanguageModel:
            "No completed text-generation model was found in LM Studio. Let the model finish installing and try again."
        case .selectedModelUnavailable(let modelKey):
            "The selected LM Studio model ‘\(modelKey)’ is not installed. Choose another model in Settings."
        case .commandTimedOut(let command):
            "LM Studio timed out while running ‘\(command)’."
        case .commandFailed(let detail):
            "LM Studio could not prepare the model. \(detail)"
        case .serverUnavailable:
            "The local LM Studio server did not become available."
        case .api(let status, let detail):
            "LM Studio returned HTTP \(status). \(detail)"
        case .invalidResponse(let detail):
            "The model returned an invalid response. \(detail)"
        case .noValidSentences:
            "The model could not produce the requested number of verified sentences. Try again."
        }
    }
}

@MainActor
protocol SentenceGenerating: AnyObject {
    var progressDidChange: ((LMStudioProgress) -> Void)? { get set }

    func generate(
        vocabulary: [PersonalCard],
        count requestedCount: Int,
        options requestedOptions: SentenceGenerationOptions,
        settings requestedSettings: LMStudioSettings
    ) async throws -> [SentenceDraft]
    func installedModels() async throws -> [LMStudioModel]
    func shutdown() async
}

@MainActor
final class LMStudioService: SentenceGenerating {

    static let modelIdentifier = "lang4self-sentences"
    static let serverURL = URL(string: "http://127.0.0.1:1234")!

    var progressDidChange: ((LMStudioProgress) -> Void)?

    private(set) var progress: LMStudioProgress = .idle {
        didSet { progressDidChange?(progress) }
    }

    private var activeProcess: Process?
    private var managedModelLoaded = false
    private var loadedSettings: LMStudioSettings?
    private var loadedModelKey: String?
    private var isShuttingDown = false

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 240
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init() {}

    func generate(
        vocabulary: [PersonalCard],
        count requestedCount: Int,
        options requestedOptions: SentenceGenerationOptions,
        settings requestedSettings: LMStudioSettings
    ) async throws -> [SentenceDraft] {
        let count = min(max(requestedCount, 1), 10)
        let options = requestedOptions.sanitized
        let settings = requestedSettings.sanitized
        let safeVocabulary = Array(vocabulary.prefix(600))
        guard !safeVocabulary.isEmpty else { throw LMStudioError.noValidSentences }
        isShuttingDown = false

        do {
            let model = try await prepareModel(settings: settings)
            progress = .generating(count, model.displayName)
            let contract = SentenceGenerationContract(vocabulary: safeVocabulary, options: options)
            let validator = GeneratedSentenceValidator(vocabulary: safeVocabulary, options: options)
            var drafts: [SentenceDraft] = []

            for attempt in 0..<3 where drafts.count < count {
                let missingCount = count - drafts.count
                let response: SentenceGenerationEnvelope
                do {
                    do {
                        response = try await requestSentences(
                            contract: contract,
                            count: missingCount,
                            settings: settings,
                            excluding: drafts.map(\.german),
                            structured: true
                        )
                    } catch LMStudioError.api(let status, _) where status == 400 || status == 422 {
                        response = try await requestSentences(
                            contract: contract,
                            count: missingCount,
                            settings: settings,
                            excluding: drafts.map(\.german),
                            structured: false
                        )
                    }
                } catch LMStudioError.invalidResponse where attempt < 2 {
                    continue
                }
                let seen = Set(drafts.map { SentenceTokenizer.normalized($0.german) })
                drafts += validator.validatedDrafts(
                    from: response,
                    limit: missingCount,
                    excluding: seen
                )
            }
            guard drafts.count == count else { throw LMStudioError.noValidSentences }
            progress = .ready(model.displayName)
            return drafts
        } catch {
            guard !isShuttingDown else { throw CancellationError() }
            progress = .failed(error.localizedDescription)
            throw error
        }
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        session.invalidateAndCancel()
        if activeProcess?.isRunning == true { activeProcess?.terminate() }
        progress = .unloading
        if cliURL != nil {
            // Always attempt this: the daemon may have completed a load just as the
            // UI task was cancelled, before managedModelLoaded could be updated.
            _ = try? await runCLI(["unload", Self.modelIdentifier], timeout: 45)
        }
        managedModelLoaded = false
        loadedSettings = nil
        loadedModelKey = nil
        progress = .idle
    }

    func installedModels() async throws -> [LMStudioModel] {
        try await readInstalledModels()
    }

    private func prepareModel(settings: LMStudioSettings) async throws -> LMStudioModel {
        progress = .findingModel
        let model = try await selectedInstalledModel(for: settings)

        if !(await serverIsAvailable()) {
            progress = .startingServer
            _ = try await runCLI(
                ["server", "start", "--port", "1234", "--bind", "127.0.0.1"],
                timeout: 30
            )
            guard await waitForServer() else { throw LMStudioError.serverUnavailable }
        }

        if try await loadedModelIDs().contains(Self.modelIdentifier) {
            if let loadedSettings,
               loadedModelKey == model.modelKey,
               !settings.requiresReload(comparedTo: loadedSettings) {
                managedModelLoaded = true
                progress = .ready(model.displayName)
                return model
            }
            progress = .unloading
            _ = try? await runCLI(["unload", Self.modelIdentifier], timeout: 45)
            managedModelLoaded = false
            loadedModelKey = nil
        }

        progress = .loadingModel(model.displayName)
        var loadArguments = [
            "load", model.modelKey,
            "--identifier", Self.modelIdentifier,
            "--context-length", String(min(settings.contextLength, model.maxContextLength ?? settings.contextLength))
        ]
        switch settings.gpuOffload {
        case .automatic: break
        case .maximum: loadArguments += ["--gpu", "max"]
        case .cpuOnly: loadArguments += ["--gpu", "off"]
        }
        loadArguments.append("--yes")
        _ = try await runCLI(loadArguments, timeout: 240)

        guard await waitForModel() else {
            throw LMStudioError.commandFailed("The model load command finished, but its API identifier was not available.")
        }
        managedModelLoaded = true
        loadedSettings = settings
        loadedModelKey = model.modelKey
        progress = .ready(model.displayName)
        return model
    }

    private func selectedInstalledModel(for settings: LMStudioSettings) async throws -> LMStudioModel {
        let models = try await readInstalledModels()
        if !settings.modelKey.isEmpty {
            guard let selected = models.first(where: { $0.modelKey == settings.modelKey }) else {
                throw LMStudioError.selectedModelUnavailable(settings.modelKey)
            }
            return selected
        }
        guard let preferred = models.first else { throw LMStudioError.noLanguageModel }
        return preferred
    }

    private func readInstalledModels() async throws -> [LMStudioModel] {
        let output = try await installedModelsOutput()
        guard let data = output.data(using: .utf8) else { throw LMStudioError.noLanguageModel }
        let models: [LMStudioModel]
        do {
            models = try JSONDecoder().decode([LMStudioModel].self, from: data).filter { $0.type == "llm" }
        } catch {
            throw LMStudioError.invalidResponse("The installed-model list could not be read.")
        }
        guard !models.isEmpty else { throw LMStudioError.noLanguageModel }

        return models.sorted { lhs, rhs in
            let left = modelPreference(lhs)
            let right = modelPreference(rhs)
            return left == right ? lhs.sizeBytes > rhs.sizeBytes : left > right
        }
    }

    private func installedModelsOutput() async throws -> String {
        do {
            return try await runCLI(["ls", "--json"], timeout: 20)
        } catch let initialError {
            guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.elementlabs.lmstudio") else {
                throw initialError
            }
            progress = .launchingStudio
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)

            for _ in 0..<60 {
                if let output = try? await runCLI(["ls", "--json"], timeout: 5) { return output }
                try? await Task.sleep(for: .milliseconds(250))
            }
            throw initialError
        }
    }

    private func modelPreference(_ model: LMStudioModel) -> Int {
        let name = (model.modelKey + " " + model.displayName).lowercased()
        if name.contains("qwen3.6") { return 50 }
        if name.contains("qwen3") && (name.contains("30b") || name.contains("35b")) { return 40 }
        if name.contains("qwen") { return 30 }
        if name.contains("gemma") { return 20 }
        return 10
    }

    private func serverIsAvailable() async -> Bool {
        do {
            var request = URLRequest(url: Self.serverURL.appendingPathComponent("v1/models"))
            request.timeoutInterval = 2
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func waitForServer() async -> Bool {
        for _ in 0..<40 {
            if await serverIsAvailable() { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func waitForModel() async -> Bool {
        for _ in 0..<40 {
            if (try? await loadedModelIDs().contains(Self.modelIdentifier)) == true { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func loadedModelIDs() async throws -> Set<String> {
        var request = URLRequest(url: Self.serverURL.appendingPathComponent("v1/models"))
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LMStudioError.serverUnavailable
        }
        let result = try JSONDecoder().decode(LoadedModelsResponse.self, from: data)
        return Set(result.data.map(\.id))
    }

    private func requestSentences(
        contract: SentenceGenerationContract,
        count: Int,
        settings: LMStudioSettings,
        excluding excludedSentences: [String],
        structured: Bool
    ) async throws -> SentenceGenerationEnvelope {
        let userPrompt = try contract.userPrompt(excluding: excludedSentences)

        var body: [String: Any] = [
            "model": Self.modelIdentifier,
            "messages": [
                ["role": "system", "content": contract.systemPrompt(count: count)],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": settings.temperature,
            "top_p": settings.topP,
            "max_tokens": SentenceGenerationContract.outputTokenLimit(
                requestedLimit: settings.maxOutputTokens,
                sentenceCount: count
            ),
            "stream": false
        ]
        if structured {
            body["response_format"] = SentenceGenerationContract.responseFormat(count: count)
        }

        var request = URLRequest(url: Self.serverURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard data.count < 2_000_000 else {
            throw LMStudioError.invalidResponse("The response was unexpectedly large.")
        }
        guard let http = response as? HTTPURLResponse else { throw LMStudioError.serverUnavailable }
        guard (200..<300).contains(http.statusCode) else {
            let detail = apiErrorMessage(from: data)
            throw LMStudioError.api(http.statusCode, detail)
        }

        let chat: ChatResponse
        do {
            chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw LMStudioError.invalidResponse("The chat response could not be decoded.")
        }
        guard let message = chat.choices.first?.message,
              let content = [message.content, message.reasoningContent]
                .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else {
            throw LMStudioError.invalidResponse("The response contained no text.")
        }
        return try contract.decodeEnvelope(content)
    }

    private func apiErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(400))
        }
        return String(data: data.prefix(400), encoding: .utf8) ?? "Unknown API error."
    }

    private var cliURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".lmstudio/bin/lms"),
            URL(fileURLWithPath: "/opt/homebrew/bin/lms"),
            URL(fileURLWithPath: "/usr/local/bin/lms")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runCLI(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        guard let cliURL else { throw LMStudioError.cliNotFound }
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = cliURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputReader = Task.detached { (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data() }
        let errorReader = Task.detached { (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data() }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            throw LMStudioError.commandFailed(error.localizedDescription)
        }
        activeProcess = process
        let startedAt = Date()
        do {
            while process.isRunning {
                try Task.checkCancellation()
                if Date().timeIntervalSince(startedAt) > timeout {
                    process.terminate()
                    throw LMStudioError.commandTimedOut(arguments.prefix(2).joined(separator: " "))
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            if process.isRunning { process.terminate() }
            activeProcess = nil
            _ = await outputReader.value
            _ = await errorReader.value
            throw error
        }
        activeProcess = nil

        let output = String(data: await outputReader.value, encoding: .utf8) ?? ""
        let errorOutput = String(data: await errorReader.value, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LMStudioError.commandFailed(String(detail.prefix(600)))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LoadedModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }
        let message: Message
    }
    let choices: [Choice]
}
