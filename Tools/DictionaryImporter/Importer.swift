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
        do {
            let prepared = try await SystemDictionaryFilePreparer().prepare(source)
            defer { prepared.cleanUp() }

            let store = try LocalStore()
            let imported = try await store.importDictionary(from: prepared.url) { progress in
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
}
