import AppKit
import AVFoundation
import Foundation

@MainActor
protocol GermanSpeechSynthesizing: AnyObject {
    func start()
    func prepare(_ text: String?)
    func speak(_ text: String)
    func stop()
}

enum GermanSpeechModelStatus: Equatable {
    case checking
    case notDownloaded
    case downloading
    case loading
    case warming
    case ready
    case failed(String)
}

@MainActor
protocol GermanSpeechModelManaging: AnyObject {
    var modelStatus: GermanSpeechModelStatus { get }
    var modelStatusDidChange: ((GermanSpeechModelStatus) -> Void)? { get set }
    func downloadModel()
}

@MainActor
final class AppleGermanSpeechSynthesizer: GermanSpeechSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let utterance = AVSpeechUtterance(string: "Hallo.")
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        synthesizer.write(utterance) { _ in }
    }

    func prepare(_ text: String?) {}

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

@MainActor
final class GermanSpeechController: ObservableObject {
    enum Context: Hashable {
        case dictionary
        case review
        case library
        case sentences
    }

    @Published private(set) var target: String?
    @Published private(set) var lastSpokenText: String?
    @Published private(set) var modelStatus: GermanSpeechModelStatus

    private let synthesizer: any GermanSpeechSynthesizing
    private let modelManager: (any GermanSpeechModelManaging)?
    private var targets: [Context: String] = [:]
    private var activeContext: Context?

    init(
        synthesizer: any GermanSpeechSynthesizing,
        modelManager: (any GermanSpeechModelManaging)? = nil
    ) {
        self.synthesizer = synthesizer
        self.modelManager = modelManager
        modelStatus = modelManager?.modelStatus ?? .notDownloaded
        modelManager?.modelStatusDidChange = { [weak self] status in
            self?.modelStatus = status
            if status == .ready, let target = self?.target {
                self?.synthesizer.prepare(target)
            }
        }
    }

    func start() {
        synthesizer.start()
    }

    func downloadModel() {
        modelManager?.downloadModel()
    }

    func activate(_ context: Context?) {
        activeContext = context
        publishTarget()
    }

    func setTarget(_ text: String?, in context: Context) {
        targets[context] = Self.normalized(text)
        if context == activeContext {
            publishTarget()
        }
    }

    func speakTarget() {
        guard let target else { return }
        speak(target)
    }

    func speak(_ text: String) {
        guard let text = Self.normalized(text) else { return }
        lastSpokenText = text
        synthesizer.speak(text)
    }

    func stop() {
        synthesizer.stop()
    }

    private func publishTarget() {
        let nextTarget = activeContext.flatMap { targets[$0] }
        guard target != nextTarget else { return }
        target = nextTarget
        synthesizer.prepare(nextTarget)
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct DoubleShiftKeyDetector {
    let maximumInterval: TimeInterval

    private var firstTapReleasedAt: TimeInterval?
    private var isShiftDown = false
    private var currentTapIsClean = false
    private var isCompletingGesture = false

    init(maximumInterval: TimeInterval = 0.4) {
        self.maximumInterval = maximumInterval
    }

    mutating func handle(_ event: NSEvent) -> Bool {
        guard event.type == .flagsChanged, Self.shiftKeyCodes.contains(event.keyCode) else {
            if event.type == .keyDown || event.type == .flagsChanged {
                currentTapIsClean = false
                firstTapReleasedAt = nil
            }
            return false
        }

        let shiftIsPressed = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift)

        if shiftIsPressed {
            guard !isShiftDown else { return false }
            isShiftDown = true
            currentTapIsClean = true

            guard let firstTapReleasedAt else { return false }
            let interval = event.timestamp - firstTapReleasedAt
            guard interval >= 0, interval <= maximumInterval else {
                self.firstTapReleasedAt = nil
                return false
            }

            self.firstTapReleasedAt = nil
            isCompletingGesture = true
            return true
        }

        guard isShiftDown else { return false }
        isShiftDown = false
        if isCompletingGesture {
            isCompletingGesture = false
            currentTapIsClean = false
            return false
        }
        if currentTapIsClean {
            firstTapReleasedAt = event.timestamp
        }
        currentTapIsClean = false
        return false
    }

    mutating func reset() {
        firstTapReleasedAt = nil
        isShiftDown = false
        currentTapIsClean = false
        isCompletingGesture = false
    }

    private static let shiftKeyCodes: Set<UInt16> = [56, 60]
}

@MainActor
final class DoubleShiftShortcutController {
    private var detector: DoubleShiftKeyDetector
    private let action: () -> Void
    private var eventMonitor: Any?

    init(
        maximumInterval: TimeInterval = 0.4,
        action: @escaping () -> Void
    ) {
        detector = DoubleShiftKeyDetector(maximumInterval: maximumInterval)
        self.action = action
    }

    func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        detector.reset()
    }

    func reset() {
        detector.reset()
    }

    func handle(_ event: NSEvent) {
        if detector.handle(event) {
            action()
        }
    }
}
