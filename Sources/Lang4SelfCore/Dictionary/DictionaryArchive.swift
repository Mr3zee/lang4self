#if os(macOS)
import Foundation

public struct PreparedDictionaryFile: Sendable {
    public let url: URL
    private let temporaryDirectory: URL?

    fileprivate init(url: URL, temporaryDirectory: URL?) {
        self.url = url
        self.temporaryDirectory = temporaryDirectory
    }

    public init(url: URL) {
        self.init(url: url, temporaryDirectory: nil)
    }

    public func cleanUp() {
        guard let temporaryDirectory else { return }
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

public protocol DictionaryFilePreparing: Sendable {
    func prepare(_ source: URL) async throws -> PreparedDictionaryFile
}

public struct SystemDictionaryFilePreparer: DictionaryFilePreparing {
    public init() {}

    public func prepare(_ source: URL) async throws -> PreparedDictionaryFile {
        try await DictionaryArchive.prepare(source)
    }
}

public enum DictionaryArchiveError: LocalizedError {
    case extractionFailed
    case noTextFile

    public var errorDescription: String? {
        switch self {
        case .extractionFailed: "The ZIP archive could not be extracted."
        case .noTextFile: "The ZIP archive does not contain a dict.cc text file."
        }
    }
}

/// Prepares a dict.cc text file for import, extracting ZIP downloads off the caller's executor.
public enum DictionaryArchive {
    public static func prepare(_ source: URL) async throws -> PreparedDictionaryFile {
        guard source.pathExtension.lowercased() == "zip" else {
            return .init(url: source, temporaryDirectory: nil)
        }

        return try await Task.detached(priority: .userInitiated) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Lang4Self-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-x", "-k", source.path, directory.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw DictionaryArchiveError.extractionFailed
                }

                let files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                guard let textFile = files
                    .filter({ $0.pathExtension.lowercased() == "txt" })
                    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                    .first
                else {
                    throw DictionaryArchiveError.noTextFile
                }
                return PreparedDictionaryFile(url: textFile, temporaryDirectory: directory)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }.value
    }
}
#endif
