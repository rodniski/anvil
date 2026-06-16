import Foundation

/// Persiste a lista de projetos em JSON. Por padrão em
/// `~/Library/Application Support/Anvil/projects.json`.
public struct ProjectStore: Sendable {
    private let fileURL: URL
    private var fileManager: FileManager { .default }

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = support
                .appendingPathComponent("Anvil", isDirectory: true)
                .appendingPathComponent("projects.json")
        }
    }

    /// Caminho do arquivo de persistência (útil pra UI e debug).
    public var location: URL { fileURL }

    public func load() throws -> [Project] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([Project].self, from: data)
    }

    public func save(_ projects: [Project]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projects)
        try data.write(to: fileURL, options: .atomic)
    }
}
