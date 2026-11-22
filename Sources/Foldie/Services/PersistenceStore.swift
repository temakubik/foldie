import Foundation

final class PersistenceStore: Sendable {
    private let configURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = appSupport.appendingPathComponent("Foldie", isDirectory: true)
        self.configURL = folder.appendingPathComponent("config.json")
    }

    func load() -> FoldieConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return FoldieConfig()
        }
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            return try decoder.decode(FoldieConfig.self, from: data)
        } catch {
            return FoldieConfig()
        }
    }

    func save(_ config: FoldieConfig) {
        do {
            let dir = configURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            // Silently ignore transient write errors
        }
    }
}
