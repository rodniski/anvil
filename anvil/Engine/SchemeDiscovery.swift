import Foundation

/// Descobre schemes (iOS) e flavors×buildTypes (Android) de um projeto.
/// "Bom o suficiente": cobre o caso comum, não todo Gradle exótico.
public struct SchemeDiscovery: Sendable {
    private let runner: ProcessRunner
    private var fileManager: FileManager { .default }

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: iOS

    /// Localiza `.xcworkspace` (preferido) ou `.xcodeproj` na raiz.
    public func xcodeContainer(in projectURL: URL) -> (flag: String, path: String)? {
        let entries = (try? fileManager.contentsOfDirectory(atPath: projectURL.path)) ?? []
        if let ws = entries.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return ("-workspace", projectURL.appendingPathComponent(ws).path)
        }
        if let proj = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return ("-project", projectURL.appendingPathComponent(proj).path)
        }
        return nil
    }

    /// `xcodebuild -list -json` → schemes.
    public func discoverSchemes(in projectURL: URL) async throws -> [Scheme] {
        guard let container = xcodeContainer(in: projectURL) else { return [] }
        let result = try await runner.run(
            "xcodebuild",
            arguments: ["-list", "-json", container.flag, container.path]
        )
        guard result.succeeded,
              let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        // A chave de topo é "project" ou "workspace".
        let inner = (json["project"] as? [String: Any]) ?? (json["workspace"] as? [String: Any])
        let names = inner?["schemes"] as? [String] ?? []
        return names.map(Scheme.init(name:))
    }

    // MARK: Android

    static let knownBuildTypes = ["debug", "release"]

    /// Localiza o wrapper `./gradlew` na raiz.
    public func gradlewPath(in projectURL: URL) -> String? {
        let path = projectURL.appendingPathComponent("gradlew").path
        return fileManager.isExecutableFile(atPath: path) ? path : nil
    }

    /// `./gradlew tasks` → extrai tasks `assemble<Flavor><BuildType>` → flavors.
    /// Gradle é a fonte da verdade (mais lento que parsear, porém confiável).
    public func discoverFlavors(in projectURL: URL) async throws -> [Flavor] {
        guard gradlewPath(in: projectURL) != nil else { return [] }
        let result = try await runner.run(
            "./gradlew",
            arguments: ["-q", "tasks", "--all"],
            workingDirectory: projectURL
        )
        guard result.succeeded else { return [] }
        return Self.parseFlavors(fromGradleTasks: result.output)
    }

    /// Extrai flavors das linhas de `gradlew tasks`. Pega tasks no formato
    /// `assembleProdDebug` / `app:assembleDebug` e separa flavor de buildType
    /// pelos buildTypes conhecidos como sufixo.
    static func parseFlavors(fromGradleTasks output: String) -> [Flavor] {
        var found = Set<Flavor>()
        for rawLine in output.split(separator: "\n") {
            // Pega a 1ª palavra da linha (o nome da task, antes do " - descrição").
            let token = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            // Remove prefixo de módulo (`app:`).
            let taskName = token.split(separator: ":").last.map(String.init) ?? token
            guard taskName.hasPrefix("assemble") else { continue }
            let suffix = String(taskName.dropFirst("assemble".count))
            guard !suffix.isEmpty else { continue }

            if let flavor = Self.split(suffix) {
                found.insert(flavor)
            }
        }
        return found.sorted { $0.id < $1.id }
    }

    /// `ProdDebug` → (flavor: "prod", buildType: "debug").
    /// `Debug` → (flavor: "", buildType: "debug").
    private static func split(_ suffix: String) -> Flavor? {
        let lower = suffix.lowercased()
        for buildType in knownBuildTypes where lower.hasSuffix(buildType) {
            let flavorPart = String(suffix.dropLast(buildType.count))
            return Flavor(
                flavor: flavorPart.lowercasedFirst,
                buildType: buildType
            )
        }
        return nil
    }

    // MARK: Bun / npm

    /// Runtime JS: `bun` se houver lockfile do bun, senão `npm`.
    public func jsRuntime(in url: URL) -> String {
        let bunLocks = ["bun.lockb", "bun.lock"]
        let has = bunLocks.contains { fileManager.fileExists(atPath: url.appendingPathComponent($0).path) }
        return has ? "bun" : "npm"
    }

    /// Scripts do `package.json` (chaves de "scripts").
    public func discoverScripts(in url: URL) async -> [String] {
        let pkg = url.appendingPathComponent("package.json")
        guard let data = fileManager.contents(atPath: pkg.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: Any]
        else { return [] }
        // Prioriza build/dev/start no topo.
        let priority = ["build", "dev", "start", "test", "lint"]
        let keys = Array(scripts.keys)
        return keys.sorted {
            let a = priority.firstIndex(of: $0) ?? Int.max
            let b = priority.firstIndex(of: $1) ?? Int.max
            return a == b ? $0 < $1 : a < b
        }
    }

    // MARK: Docker

    /// Caminho do compose se existir; senão nil (modo Dockerfile).
    public func composeFile(in url: URL) -> String? {
        ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"]
            .first { fileManager.fileExists(atPath: url.appendingPathComponent($0).path) }
    }

    /// Serviços do compose (parse leve por indentação sob `services:`).
    public func discoverDockerServices(in url: URL) async -> [String] {
        guard let file = composeFile(in: url),
              let text = try? String(contentsOf: url.appendingPathComponent(file), encoding: .utf8)
        else { return [] }
        var services: [String] = []
        var inServices = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            if line.hasPrefix("services:") { inServices = true; continue }
            guard inServices else { continue }
            // Top-level key (sem indent) encerra a seção services.
            if !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            // Serviço = chave indentada 2 espaços, terminando em ":".
            if let m = line.range(of: #"^\s{2}([A-Za-z0-9._-]+):"#, options: .regularExpression) {
                let key = line[m].trimmingCharacters(in: CharacterSet(charactersIn: " :"))
                if !key.isEmpty { services.append(key) }
            }
        }
        return services
    }
}

extension String {
    /// Primeira letra minúscula (`Prod` → `prod`).
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
