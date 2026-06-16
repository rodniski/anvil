import Foundation

public enum BuildMode: String, Sendable, CaseIterable {
    case build
    case run
}

/// Comando concreto a ser executado para um build — separado da execução
/// pra poder ser testado por inspeção, sem rodar nada.
public struct BuildCommand: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: URL?
    public var environment: [String: String]

    public init(executable: String, arguments: [String], workingDirectory: URL? = nil, environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    /// Linha de comando legível pro console ("▸ xcodebuild …").
    public var display: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

/// Monta e dispara builds. A montagem do comando é pura (testável); a execução
/// delega no `ProcessRunner` e devolve o stream de eventos.
public struct BuildRunner: Sendable {
    private let runner: ProcessRunner
    private let discovery: SchemeDiscovery

    public init(runner: ProcessRunner = ProcessRunner(), discovery: SchemeDiscovery = SchemeDiscovery()) {
        self.runner = runner
        self.discovery = discovery
    }

    public enum BuildError: Error, Sendable, CustomStringConvertible {
        case missingSelection(Platform)
        case noContainer(Platform)

        public var description: String {
            switch self {
            case .missingSelection(let p): "Faltam seleções para \(p.rawValue) (scheme/flavor ou device)."
            case .noContainer(let p): "Nenhum projeto \(p.rawValue) encontrado na pasta."
            }
        }
    }

    // MARK: Montagem do comando (pura)

    public func command(for component: Component, mode: BuildMode) throws -> BuildCommand {
        switch component.platform {
        case .ios:     try iosCommand(component: component, mode: mode)
        case .android: try androidCommand(component: component, mode: mode)
        case .bun:     bunCommand(component: component, mode: mode)
        case .docker:  dockerCommand(component: component, mode: mode)
        }
    }

    /// PATH aumentado — apps de GUI não herdam o PATH do shell, então `bun`/
    /// `docker`/`node` não seriam encontrados. Inclui os locais comuns.
    private func toolEnv(_ extra: [String: String] = [:]) -> [String: String] {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let dirs = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "\(home)/.bun/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin",
            "\(home)/.nvm/current/bin", "/usr/bin", "/bin",
        ]
        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var env = extra
        env["PATH"] = (dirs + [current]).joined(separator: ":")
        return env
    }

    private func bunCommand(component: Component, mode: BuildMode) -> BuildCommand {
        let runtime = discovery.jsRuntime(in: component.path)   // bun ou npm
        // build → script selecionado; run → "dev" (fallback "start").
        let selected = component.selection.task ?? component.tasks.first ?? "build"
        let script: String = {
            guard mode == .run else { return selected }
            if component.tasks.contains("dev") { return "dev" }
            if component.tasks.contains("start") { return "start" }
            return selected
        }()
        var extra: [String: String] = [:]
        if let envv = component.selection.environment, !envv.isEmpty { extra["NODE_ENV"] = envv }
        return BuildCommand(executable: runtime, arguments: ["run", script],
                            workingDirectory: component.path, environment: toolEnv(extra))
    }

    private func dockerCommand(component: Component, mode: BuildMode) -> BuildCommand {
        let verb = (mode == .run) ? "up" : "build"   // up anexado → logs no console
        if discovery.composeFile(in: component.path) != nil {
            var args = ["compose", verb]
            // Sem serviço selecionado = stack inteiro; senão mira um serviço.
            if let svc = component.selection.task, !svc.isEmpty { args.append(svc) }
            return BuildCommand(executable: "docker", arguments: args,
                                workingDirectory: component.path, environment: toolEnv())
        }
        // Só Dockerfile: build/run pela tag = nome do componente.
        let tag = component.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let args = (verb == "up")
            ? ["run", "--rm", tag]
            : ["build", "-t", tag, "."]
        return BuildCommand(executable: "docker", arguments: args,
                            workingDirectory: component.path, environment: toolEnv())
    }

    private func iosCommand(component: Component, mode: BuildMode) throws -> BuildCommand {
        let selection = component.selection
        guard let scheme = selection.iosScheme, !scheme.isEmpty else {
            throw BuildError.missingSelection(.ios)
        }
        guard let container = discovery.xcodeContainer(in: component.path) else {
            throw BuildError.noContainer(.ios)
        }

        var args = [container.flag, container.path, "-scheme", scheme]
        if let udid = selection.iosSimulator, !udid.isEmpty {
            args += ["-destination", "platform=iOS Simulator,id=\(udid)"]
        }
        // build e run usam o mesmo xcodebuild build; lançar no simulador
        // (install+launch via simctl) é evolução pós-MVP.
        args.append("build")

        var env: [String: String] = [:]
        if let xcodePath = selection.iosXcode, !xcodePath.isEmpty {
            env["DEVELOPER_DIR"] = "\(xcodePath)/Contents/Developer"
        }
        if let environment = selection.iosEnvironment, !environment.isEmpty {
            env["ANVIL_ENV"] = environment
        }

        return BuildCommand(executable: "xcodebuild", arguments: args, workingDirectory: component.path, environment: env)
    }

    private func androidCommand(component: Component, mode: BuildMode) throws -> BuildCommand {
        let selection = component.selection
        guard let flavorID = selection.androidFlavor, !flavorID.isEmpty,
              let flavor = component.androidTargets.first(where: { $0.id == flavorID })
        else {
            throw BuildError.missingSelection(.android)
        }

        // build → assembleProdDebug · run → installProdDebug (compila e instala no device ativo).
        let verb = (mode == .run) ? "install" : "assemble"
        let task = verb + flavor.gradleSuffix

        var env: [String: String] = [:]
        if let environment = selection.androidEnvironment, !environment.isEmpty {
            env["ANVIL_ENV"] = environment
        }

        return BuildCommand(executable: "./gradlew", arguments: [task], workingDirectory: component.path, environment: env)
    }

    // MARK: Execução

    /// Dispara o comando e devolve o stream de eventos em tempo real.
    public func run(_ command: BuildCommand) -> AsyncThrowingStream<ProcessEvent, Error> {
        runner.stream(
            command.executable,
            arguments: command.arguments,
            workingDirectory: command.workingDirectory,
            environment: command.environment.isEmpty ? nil : command.environment
        )
    }
}
