import Foundation
import Lang4SelfCore

@main
enum Lang4SelfDictionaryImporter {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("Usage: Lang4SelfDictionaryImporter <dict.cc .zip or .txt>\n".utf8))
            Foundation.exit(2)
        }

        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        var temporaryDirectory: URL?
        do {
            let textFile: URL
            if source.pathExtension.lowercased() == "zip" {
                let prepared = try extract(source)
                textFile = prepared.file
                temporaryDirectory = prepared.directory
            } else {
                textFile = source
            }
            defer {
                if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
            }

            let store = try LocalStore()
            let imported = try await store.importDictionary(from: textFile) { progress in
                if progress.imported % 100_000 < 15_000 {
                    print("Imported \(progress.imported.formatted()) entries…")
                }
            }
            print("Done: \(imported.formatted()) entries in \(store.databaseURL.path)")
        } catch {
            FileHandle.standardError.write(Data("Import failed: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func extract(_ archive: URL) throws -> (file: URL, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lang4Self-Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, directory.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ImporterError.extractionFailed }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard let textFile = files.first(where: { $0.pathExtension.lowercased() == "txt" }) else {
                throw ImporterError.noTextFile
            }
            return (textFile, directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private enum ImporterError: LocalizedError {
        case extractionFailed
        case noTextFile

        var errorDescription: String? {
            switch self {
            case .extractionFailed: "Could not extract ZIP archive"
            case .noTextFile: "No text file found in ZIP archive"
            }
        }
    }
}
