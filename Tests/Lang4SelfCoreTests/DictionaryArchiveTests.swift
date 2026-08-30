#if os(macOS)
import Foundation
import XCTest
@testable import Lang4SelfCore

final class DictionaryArchiveTests: XCTestCase {
    func testPlainTextFileNeedsNoPreparationOrCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("dictionary.txt")
        try Data("Haus {n}\thouse\n".utf8).write(to: source)

        let prepared = try await DictionaryArchive.prepare(source)
        prepared.cleanUp()

        XCTAssertEqual(prepared.url, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testExtractsDictionaryTextFromZip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("dictionary.txt")
        let archive = directory.appendingPathComponent("dictionary.zip")
        try Data("Haus {n}\thouse\n".utf8).write(to: source)
        try runDitto(["-c", "-k", source.path, archive.path])

        let prepared = try await DictionaryArchive.prepare(archive)
        let extractedURL = prepared.url
        defer { prepared.cleanUp() }

        XCTAssertEqual(try String(contentsOf: extractedURL, encoding: .utf8), "Haus {n}\thouse\n")
        prepared.cleanUp()
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractedURL.path))
    }

    private func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
#endif
