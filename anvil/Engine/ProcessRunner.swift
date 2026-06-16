import Foundation

/// Uma linha de saída de um processo, com origem.
public struct LogLine: Sendable, Hashable {
    public enum Source: Sendable, Hashable { case stdout, stderr }
    public var source: Source
    public var text: String

    public init(source: Source, text: String) {
        self.source = source
        self.text = text
    }
}

/// Consumo de recursos da árvore de processos da build, num instante.
public struct ProcessMetrics: Sendable, Hashable {
    /// Soma de %CPU da árvore (pode passar de 100 em multicore).
    public var cpu: Double
    /// Memória residente somada, em MB.
    public var memoryMB: Double

    public init(cpu: Double, memoryMB: Double) {
        self.cpu = cpu
        self.memoryMB = memoryMB
    }
}

/// Evento emitido durante a execução de um processo.
public enum ProcessEvent: Sendable {
    case line(LogLine)
    case metrics(ProcessMetrics)
    case finished(exitCode: Int32)
}

/// Resultado final agregado de um processo.
public struct ProcessResult: Sendable {
    public var exitCode: Int32
    /// stdout + stderr concatenados, na ordem de chegada.
    public var output: String
    public var succeeded: Bool { exitCode == 0 }
}

public enum ProcessError: Error, Sendable, CustomStringConvertible {
    case launchFailed(String)

    public var description: String {
        switch self {
        case .launchFailed(let why): "Falha ao iniciar processo: \(why)"
        }
    }
}

/// Executa subprocessos. Toda chamada externa (`xcodebuild`, `gradlew`,
/// `simctl`, `adb`, …) passa por aqui — a engine nunca espalha `Process`
/// pelo código.
public struct ProcessRunner: Sendable {
    public init() {}

    /// PATH com os locais comuns de ferramentas (homebrew, bun, etc.) — apps
    /// de GUI não herdam o PATH do shell.
    static let augmentedPATH: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let dirs = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "\(home)/.bun/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (dirs + (current.isEmpty ? [] : [current])).joined(separator: ":")
    }()

    /// Roda um comando e devolve um stream de eventos em tempo real:
    /// `.line` por linha de saída, e um `.finished` final com o exit-code.
    public func stream(
        _ executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<ProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            // Absoluto roda direto; relativo (`./gradlew`) resolve contra a pasta
            // de trabalho; nome simples vai pelo PATH via /usr/bin/env.
            if executable.hasPrefix("/") {
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
            } else if executable.hasPrefix(".") {
                let base = workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                process.executableURL = URL(fileURLWithPath: executable, relativeTo: base).standardizedFileURL
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [executable] + arguments
            }
            if let workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }
            // PATH sempre aumentado (apps de GUI não herdam o PATH do shell),
            // depois sobrescreve com o env passado.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = Self.augmentedPATH
            if let environment { env.merge(environment) { _, new in new } }
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Bufferiza bytes parciais até fechar uma linha em '\n'.
            let stdoutBuffer = LineBuffer(source: .stdout) { continuation.yield(.line($0)) }
            let stderrBuffer = LineBuffer(source: .stderr) { continuation.yield(.line($0)) }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    stdoutBuffer.flush()
                } else {
                    stdoutBuffer.feed(data)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    stderrBuffer.flush()
                } else {
                    stderrBuffer.feed(data)
                }
            }

            // Amostra o consumo da árvore de processos ~1Hz enquanto roda.
            let metricsTaskBox = TaskBox()

            process.terminationHandler = { proc in
                metricsTaskBox.cancel()
                // Garante que qualquer resto bufferizado saia antes do .finished.
                stdoutBuffer.flush()
                stderrBuffer.flush()
                continuation.yield(.finished(exitCode: proc.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { reason in
                metricsTaskBox.cancel()
                if case .cancelled = reason, process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
                let pid = process.processIdentifier
                let sampler = ResourceSampler()
                metricsTaskBox.task = Task.detached {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        if Task.isCancelled { break }
                        if let m = sampler.sample(rootPID: pid) {
                            continuation.yield(.metrics(m))
                        }
                    }
                }
            } catch {
                continuation.finish(throwing: ProcessError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Roda um comando até o fim e devolve a saída agregada.
    /// Conveniente para consultas rápidas (`simctl list`, `xcodebuild -list`).
    /// Não lança em exit-code != 0 — devolve no `ProcessResult`.
    public func run(
        _ executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        var output = ""
        var code: Int32 = -1
        for try await event in stream(executable, arguments: arguments,
                                      workingDirectory: workingDirectory,
                                      environment: environment) {
            switch event {
            case .line(let line):
                output += line.text + "\n"
            case .metrics:
                break
            case .finished(let exitCode):
                code = exitCode
            }
        }
        return ProcessResult(exitCode: code, output: output)
    }
}

/// Acumula bytes e emite uma `LogLine` por quebra de linha. `flush()` libera
/// o resto sem newline final. Thread-safe via lock — os readabilityHandlers
/// rodam em filas próprias.
private final class LineBuffer: @unchecked Sendable {
    private let source: LogLine.Source
    private let emit: @Sendable (LogLine) -> Void
    private var pending = Data()
    private let lock = NSLock()
    private let newline = UInt8(ascii: "\n")

    init(source: LogLine.Source, emit: @escaping @Sendable (LogLine) -> Void) {
        self.source = source
        self.emit = emit
    }

    func feed(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        while let idx = pending.firstIndex(of: newline) {
            let lineData = pending[pending.startIndex..<idx]
            emit(LogLine(source: source, text: String(decoding: lineData, as: UTF8.self)))
            pending.removeSubrange(pending.startIndex...idx)
        }
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return }
        emit(LogLine(source: source, text: String(decoding: pending, as: UTF8.self)))
        pending.removeAll()
    }
}

/// Caixa thread-safe pra um Task cancelável (criado depois dos handlers).
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<Void, Never>?

    var task: Task<Void, Never>? {
        get { lock.lock(); defer { lock.unlock() }; return _task }
        set { lock.lock(); defer { lock.unlock() }; _task = newValue }
    }

    func cancel() {
        lock.lock(); let t = _task; lock.unlock()
        t?.cancel()
    }
}
