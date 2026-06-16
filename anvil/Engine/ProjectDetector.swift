import Foundation

/// Classifica uma pasta como iOS, Android ou ambos, olhando os marcadores
/// na raiz: `.xcodeproj`/`.xcworkspace` → iOS, `settings.gradle(.kts)` → Android.
public struct ProjectDetector: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    public enum DetectionError: Error, Sendable, CustomStringConvertible {
        case notADirectory(URL)
        case nothingFound(URL)

        public var description: String {
            switch self {
            case .notADirectory(let url): "Não é uma pasta: \(url.path)"
            case .nothingFound(let url):
                "Nenhum componente reconhecido em \(url.path) (iOS, Android, Bun/npm ou Docker)"
            }
        }
    }

    /// Detecta os tipos de componente presentes na pasta (pode ter mais de um).
    public func detect(at url: URL) throws -> [Platform] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw DetectionError.notADirectory(url)
        }

        let entries = Set((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? [])
        var kinds: [Platform] = []

        if entries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            kinds.append(.ios)
        }
        if entries.contains("settings.gradle") || entries.contains("settings.gradle.kts") {
            kinds.append(.android)
        }
        if entries.contains("package.json") {
            kinds.append(.bun)
        }
        if entries.contains("Dockerfile") || entries.contains("docker-compose.yml")
            || entries.contains("docker-compose.yaml") || entries.contains("compose.yml")
            || entries.contains("compose.yaml") {
            kinds.append(.docker)
        }

        guard !kinds.isEmpty else { throw DetectionError.nothingFound(url) }
        return kinds
    }

    /// Nome sugerido para o projeto: o nome da pasta raiz.
    public func suggestedName(for url: URL) -> String {
        url.lastPathComponent
    }
}
