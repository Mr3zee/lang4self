import Foundation

struct PreparedDictionaryFile: Sendable {
    let url: URL
    let temporaryDirectory: URL?

    func cleanUp() {
        guard let temporaryDirectory else { return }
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

enum DictionaryArchiveError: LocalizedError {
    case extractionFailed
    case noTextFile

    var errorDescription: String? {
        switch self {
        case .extractionFailed: "The ZIP archive could not be extracted."
        case .noTextFile: "The ZIP archive does not contain a dict.cc text file."
        }
    }
}

enum DictionaryArchive {
    static func prepare(_ source: URL) async throws -> PreparedDictionaryFile {
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
                guard process.terminationStatus == 0 else { throw DictionaryArchiveError.extractionFailed }

                let files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                guard let textFile = files.first(where: { $0.pathExtension.lowercased() == "txt" }) else {
                    throw DictionaryArchiveError.noTextFile
                }
                return .init(url: textFile, temporaryDirectory: directory)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }.value
    }
}
