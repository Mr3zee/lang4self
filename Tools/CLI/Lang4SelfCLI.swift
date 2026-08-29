import Darwin
import Foundation
import Lang4SelfCore

@main
enum Lang4SelfCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "open"
        do {
            switch command {
            case "open":
                try openDesktopApp()
            case "search":
                try await search(Array(arguments.dropFirst()))
            case "stats":
                try await showStats()
            case "database":
                let store = try LocalStore()
                print(store.databaseURL.path)
            case "import":
                guard let path = arguments.dropFirst().first else { throw CLIError.missingImportPath }
                try await importDictionary(URL(fileURLWithPath: path))
            case "import-explanations":
                guard let path = arguments.dropFirst().first else { throw CLIError.missingImportPath }
                try await importExplanations(URL(fileURLWithPath: path))
            case "help", "--help", "-h":
                printHelp()
            case "version", "--version", "-v":
                print("lang4self 1.0")
            default:
                // Typing `lang4self Haus` is a convenient shorthand for search.
                try await search(arguments)
            }
        } catch {
            FileHandle.standardError.write(Data("lang4self: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func openDesktopApp() throws {
        let desktopApp = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Lang4Self.app")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = FileManager.default.fileExists(atPath: desktopApp.path)
            ? [desktopApp.path]
            : ["-b", "com.alexsysoev.Lang4Self"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError.appNotInstalled }
    }

    private static func search(_ terms: [String]) async throws {
        let query = terms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw CLIError.missingSearchTerm }
        let store = try LocalStore()
        let entries = try await store.searchDictionary(query, limit: 20)
        guard !entries.isEmpty else {
            print("No results for “\(query)”.")
            return
        }
        for entry in entries {
            let article = entry.gender == .unknown ? "" : entry.gender.article.replacingOccurrences(of: " (plural)", with: "") + " "
            let translations = entry.meanings
                .map { "[\($0.language.shortLabel)] \($0.translation)" }
                .joined(separator: "; ")
            print("\(article)\(entry.german)\t\(translations)\t[\(entry.kind.label)]")
        }
    }

    private static func showStats() async throws {
        let store = try LocalStore()
        let stats = try await store.stats()
        let count = try await store.dictionaryCount()
        print("Dictionary: \(count.formatted()) entries")
        print("My words:   \(stats.totalCards.formatted())")
        print("Due now:    \(stats.dueCards.formatted())")
        print("Today:      \(stats.reviewsToday.formatted()) reviews")
        print("Streak:     \(stats.streakDays.formatted()) days")
    }

    private static func importDictionary(_ source: URL) async throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw CLIError.fileNotFound(source.path) }
        let prepared = try prepare(source)
        defer { if let directory = prepared.temporaryDirectory { try? FileManager.default.removeItem(at: directory) } }
        let store = try LocalStore()
        let imported = try await store.importDictionary(from: prepared.file) { progress in
            if progress.imported % 100_000 < 15_000 {
                FileHandle.standardError.write(Data("Imported \(progress.imported.formatted())…\n".utf8))
            }
        }
        print("Imported \(imported.formatted()) entries.")
    }

    private static func importExplanations(_ source: URL) async throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw CLIError.fileNotFound(source.path) }
        let store = try LocalStore()
        let imported = try await store.importExplanations(from: source) { progress in
            if progress.imported % 50_000 < 5_000 {
                FileHandle.standardError.write(Data("Imported \(progress.imported.formatted()) of \(progress.total.formatted()) explanations…\n".utf8))
            }
        }
        print("Imported \(imported.formatted()) explanations.")
    }

    private static func prepare(_ source: URL) throws -> (file: URL, temporaryDirectory: URL?) {
        guard source.pathExtension.lowercased() == "zip" else { return (source, nil) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lang4Self-CLI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", source.path, directory.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CLIError.extractionFailed }
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard let text = contents.first(where: { $0.pathExtension.lowercased() == "txt" }) else {
                throw CLIError.noTextFile
            }
            return (text, directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func printHelp() {
        print("""
        Lang4Self — local German learning

        Usage:
          lang4self                 Open the desktop app
          lang4self open            Open the desktop app
          lang4self search <word>   Search German, English, or Russian
          lang4self <word>          Search shorthand
          lang4self stats           Show local study statistics
          lang4self database        Print the SQLite database path
          lang4self import <file>   Import a dict.cc ZIP or text file
          lang4self import-explanations <database-de.db>
                                    Import Wiktionary explanations
          lang4self version         Print the CLI version
        """)
    }

    private enum CLIError: LocalizedError {
        case appNotInstalled
        case missingSearchTerm
        case missingImportPath
        case fileNotFound(String)
        case extractionFailed
        case noTextFile

        var errorDescription: String? {
            switch self {
            case .appNotInstalled: "Desktop app is not installed. Run scripts/install.sh."
            case .missingSearchTerm: "Provide a German, English, or Russian search term."
            case .missingImportPath: "Provide a dict.cc ZIP or text-file path."
            case .fileNotFound(let path): "File not found: \(path)"
            case .extractionFailed: "Could not extract the ZIP archive."
            case .noTextFile: "No text dictionary was found inside the ZIP archive."
            }
        }
    }
}
