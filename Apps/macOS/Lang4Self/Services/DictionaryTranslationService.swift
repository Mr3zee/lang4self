import Foundation
import SwiftUI
import Translation
import Lang4SelfCore

protocol DictionaryIndexSearching: Sendable {
    func searchDictionary(_ query: String, limit: Int) async throws -> [DictionaryEntry]
}

extension LocalStore: DictionaryIndexSearching {}

enum DictionaryTranslationPhase: Equatable {
    case idle
    case checkingAvailability
    case downloadingLanguages
    case translating
}

@MainActor
protocol DictionaryTranslating: AnyObject {
    var phaseDidChange: ((DictionaryTranslationPhase) -> Void)? { get set }
    func translateGermanToEnglish(_ text: String) async throws -> String?
}

@MainActor
protocol DictionarySearching: AnyObject {
    var translationPhaseDidChange: ((DictionaryTranslationPhase) -> Void)? { get set }
    func search(_ query: String, limit: Int) async throws -> [DictionaryEntry]
}

@MainActor
final class DictionarySearchService: DictionarySearching {
    private let index: any DictionaryIndexSearching
    private let translator: any DictionaryTranslating
    var translationPhaseDidChange: ((DictionaryTranslationPhase) -> Void)? {
        didSet { translator.phaseDidChange = translationPhaseDidChange }
    }

    init(
        index: any DictionaryIndexSearching,
        translator: any DictionaryTranslating
    ) {
        self.index = index
        self.translator = translator
    }

    func search(_ query: String, limit: Int = 80) async throws -> [DictionaryEntry] {
        let indexedResults = try await index.searchDictionary(query, limit: limit)
        guard indexedResults.isEmpty else { return indexedResults }

        let german = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !german.isEmpty,
              let translated = try await translator.translateGermanToEnglish(german)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !translated.isEmpty else {
            return []
        }
        return [DictionaryEntry(
            german: german,
            english: translated,
            kind: german.split(whereSeparator: \Character.isWhitespace).count > 1 ? .phrase : .other,
            source: DictionaryEntry.appleTranslationSource
        )]
    }
}

@MainActor
final class UnavailableDictionaryTranslator: DictionaryTranslating {
    var phaseDidChange: ((DictionaryTranslationPhase) -> Void)?

    func translateGermanToEnglish(_ text: String) async throws -> String? { nil }
}

@MainActor
final class UITestingDictionaryTranslator: DictionaryTranslating {
    var phaseDidChange: ((DictionaryTranslationPhase) -> Void)?

    func translateGermanToEnglish(_ text: String) async throws -> String? {
        let translation: String
        switch text {
        case "Dieser Satz wird lokal übersetzt.":
            translation = "This sentence is translated locally."
        case "Donaudampfschifffahrtsgesellschaftskapitän":
            translation = "Danube steamship company captain"
        default:
            return nil
        }
        defer { phaseDidChange?(.idle) }
        phaseDidChange?(.downloadingLanguages)
        try await Task.sleep(for: .seconds(3))
        phaseDidChange?(.translating)
        return translation
    }
}

@available(macOS 15.0, *)
@MainActor
final class AppleLocalTranslator: ObservableObject, DictionaryTranslating {
    private struct PendingRequest {
        let id: UUID
        let text: String
        let continuation: CheckedContinuation<String?, Error>
    }

    @Published fileprivate var configuration: TranslationSession.Configuration?
    var phaseDidChange: ((DictionaryTranslationPhase) -> Void)?
    private var pendingRequest: PendingRequest?
    private var activeRequestID: UUID?
    private var activeSession: TranslationSession?
    private var activeSessionAttemptID: UUID?
    private var installationMonitorTask: Task<Void, Never>?

    private let sourceLanguage = Locale.Language(identifier: "de")
    private let targetLanguage = Locale.Language(identifier: "en")

    func translateGermanToEnglish(_ text: String) async throws -> String? {
        let requestID = UUID()
        beginRequest(requestID)
        return try await withTaskCancellationHandler {
            do {
                let result = try await performTranslation(text, requestID: requestID)
                completeDirectRequest(requestID)
                return result
            } catch {
                completeDirectRequest(requestID)
                throw error
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(requestID)
            }
        }
    }

    private func performTranslation(_ text: String, requestID: UUID) async throws -> String? {
        try Task.checkCancellation()
        let status = await LanguageAvailability().status(
            from: sourceLanguage,
            to: targetLanguage
        )
        try Task.checkCancellation()
        guard activeRequestID == requestID else { throw CancellationError() }

        switch status {
        case .installed:
            updatePhase(.translating, requestID: requestID)
            if #available(macOS 26.0, *) {
                let session = TranslationSession(
                    installedSource: sourceLanguage,
                    target: targetLanguage
                )
                activeSession = session
                let response = try await session.translate(text)
                try Task.checkCancellation()
                return cleaned(response.targetText)
            }
            return try await requestHostedTranslation(
                text,
                requestID: requestID,
                monitorInstallation: false
            )
        case .supported:
            updatePhase(.downloadingLanguages, requestID: requestID)
            return try await requestHostedTranslation(
                text,
                requestID: requestID,
                monitorInstallation: true
            )
        case .unsupported:
            return nil
        @unknown default:
            return nil
        }
    }

    private func requestHostedTranslation(
        _ text: String,
        requestID: UUID,
        monitorInstallation: Bool
    ) async throws -> String? {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingRequest = PendingRequest(
                    id: requestID,
                    text: text,
                    continuation: continuation
                )
                if configuration == nil {
                    configuration = TranslationSession.Configuration(
                        source: sourceLanguage,
                        target: targetLanguage
                    )
                } else {
                    configuration?.invalidate()
                }
                if monitorInstallation {
                    startInstallationMonitor(requestID: requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(requestID)
            }
        }
    }

    fileprivate func fulfillPendingRequest(using session: TranslationSession) async {
        guard let request = pendingRequest else { return }
        let attemptID = UUID()
        activeSession = session
        activeSessionAttemptID = attemptID
        do {
            let status = await LanguageAvailability().status(
                from: sourceLanguage,
                to: targetLanguage
            )
            if status != .installed {
                updatePhase(.downloadingLanguages, requestID: request.id)
                try await session.prepareTranslation()
            }
            try Task.checkCancellation()
            updatePhase(.translating, requestID: request.id)
            let response = try await session.translate(request.text)
            guard activeSessionAttemptID == attemptID else { return }
            finish(request.id, result: .success(cleaned(response.targetText)))
        } catch {
            guard activeSessionAttemptID == attemptID else { return }
            finish(request.id, result: .failure(error))
        }
    }

    private func beginRequest(_ requestID: UUID) {
        if let pendingID = pendingRequest?.id {
            finish(pendingID, result: .failure(CancellationError()))
        }
        installationMonitorTask?.cancel()
        if #available(macOS 26.0, *) { activeSession?.cancel() }
        activeSession = nil
        activeSessionAttemptID = nil
        activeRequestID = requestID
        phaseDidChange?(.checkingAvailability)
    }

    private func startInstallationMonitor(requestID: UUID) {
        installationMonitorTask?.cancel()
        installationMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled,
                      let self,
                      self.pendingRequest?.id == requestID else { return }
                let status = await LanguageAvailability().status(
                    from: self.sourceLanguage,
                    to: self.targetLanguage
                )
                guard status == .installed else { continue }
                await self.resumeAfterInstallation(requestID: requestID)
                return
            }
        }
    }

    private func resumeAfterInstallation(requestID: UUID) async {
        guard let request = pendingRequest, request.id == requestID else { return }
        activeSessionAttemptID = nil
        if #available(macOS 26.0, *) {
            activeSession?.cancel()
            updatePhase(.translating, requestID: requestID)
            do {
                let session = TranslationSession(
                    installedSource: sourceLanguage,
                    target: targetLanguage
                )
                activeSession = session
                let response = try await session.translate(request.text)
                finish(requestID, result: .success(cleaned(response.targetText)))
            } catch {
                finish(requestID, result: .failure(error))
            }
        } else {
            activeSession = nil
            updatePhase(.translating, requestID: requestID)
            configuration?.invalidate()
        }
    }

    private func cleaned(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func updatePhase(_ phase: DictionaryTranslationPhase, requestID: UUID) {
        guard activeRequestID == requestID else { return }
        phaseDidChange?(phase)
    }

    private func cancel(_ requestID: UUID) {
        if pendingRequest?.id == requestID {
            finish(requestID, result: .failure(CancellationError()))
        } else {
            completeDirectRequest(requestID)
        }
    }

    private func finish(_ requestID: UUID, result: Result<String?, Error>) {
        guard pendingRequest?.id == requestID else { return }
        let continuation = pendingRequest?.continuation
        pendingRequest = nil
        completeDirectRequest(requestID)
        switch result {
        case .success(let translation): continuation?.resume(returning: translation)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    private func completeDirectRequest(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        installationMonitorTask?.cancel()
        installationMonitorTask = nil
        if #available(macOS 26.0, *) { activeSession?.cancel() }
        else { configuration?.invalidate() }
        activeSession = nil
        activeSessionAttemptID = nil
        activeRequestID = nil
        phaseDidChange?(.idle)
    }
}

private struct DictionaryTranslationHostModifier: ViewModifier {
    let translator: any DictionaryTranslating

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *),
           let appleTranslator = translator as? AppleLocalTranslator {
            content.modifier(AppleLocalTranslationModifier(translator: appleTranslator))
        } else {
            content
        }
    }
}

@available(macOS 15.0, *)
private struct AppleLocalTranslationModifier: ViewModifier {
    @ObservedObject var translator: AppleLocalTranslator

    func body(content: Content) -> some View {
        content.translationTask(translator.configuration) { session in
            await translator.fulfillPendingRequest(using: session)
        }
    }
}

extension View {
    func hostsDictionaryTranslation(using translator: any DictionaryTranslating) -> some View {
        modifier(DictionaryTranslationHostModifier(translator: translator))
    }
}
