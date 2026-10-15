import Foundation

enum KeychainStore {
    private static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scribe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    private struct Config: Codable {
        var groqAPIKey: String
    }

    static func save(_ key: String) {
        let config = Config(groqAPIKey: key)
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    static func load() -> String? {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        return config.groqAPIKey
    }

    static func clear() {
        try? FileManager.default.removeItem(at: configURL)
    }
}
