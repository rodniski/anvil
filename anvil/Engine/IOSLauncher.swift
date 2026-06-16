import Foundation

/// Executa o Run completo de iOS: compila para o simulador, localiza o `.app`,
/// boota o simulador, instala e lança — emitindo tudo como um único stream de
/// eventos (consumido igual a um build comum).
public struct IOSLauncher: Sendable {
    private let runner: ProcessRunner
    private let discovery: SchemeDiscovery
    private var fileManager: FileManager { .default }

    public init(runner: ProcessRunner = ProcessRunner(), discovery: SchemeDiscovery = SchemeDiscovery()) {
        self.runner = runner
        self.discovery = discovery
    }

    public func run(component: Component, derivedData: URL) -> AsyncThrowingStream<ProcessEvent, Error> {
        let selection = component.selection
        return AsyncThrowingStream { continuation in
            let work = Task {
                func info(_ text: String) { continuation.yield(.line(LogLine(source: .stdout, text: text))) }
                func err(_ text: String)  { continuation.yield(.line(LogLine(source: .stderr, text: text))) }
                func finish(_ code: Int32) { continuation.yield(.finished(exitCode: code)); continuation.finish() }

                guard let scheme = selection.iosScheme, !scheme.isEmpty else {
                    err("Faltou o scheme."); finish(1); return
                }
                guard let container = discovery.xcodeContainer(in: component.path) else {
                    err("Nenhum .xcodeproj/.xcworkspace na pasta."); finish(1); return
                }
                guard let udid = selection.iosSimulator, !udid.isEmpty else {
                    err("Nenhum simulador selecionado."); finish(1); return
                }

                var env: [String: String] = [:]
                if let xcode = selection.iosXcode, !xcode.isEmpty {
                    env["DEVELOPER_DIR"] = "\(xcode)/Contents/Developer"
                }

                // 1. Build para o simulador, isolando os produtos em derivedData.
                info("▸ [1/4] xcodebuild build")
                let buildArgs = [
                    container.flag, container.path,
                    "-scheme", scheme,
                    "-destination", "platform=iOS Simulator,id=\(udid)",
                    "-derivedDataPath", derivedData.path,
                    "build",
                ]
                let buildCode = await forward("xcodebuild", buildArgs, component.path, env, continuation)
                if buildCode != 0 { err("✗ build falhou (\(buildCode))"); finish(buildCode); return }

                // 2. Localizar o .app gerado.
                guard let app = locateApp(in: derivedData) else {
                    err("✗ .app não encontrado em Build/Products."); finish(1); return
                }
                guard let bundleID = bundleIdentifier(of: app) else {
                    err("✗ não consegui ler o CFBundleIdentifier de \(app.lastPathComponent)."); finish(1); return
                }
                info("▸ app: \(app.lastPathComponent) · \(bundleID)")

                // 3. Bootar o simulador (ignora se já está booted) e trazer o Simulator pra frente.
                info("▸ [2/4] boot do simulador")
                _ = try? await runner.run("xcrun", arguments: ["simctl", "boot", udid])
                _ = try? await runner.run("open", arguments: ["-a", "Simulator"])

                // 4. Instalar.
                info("▸ [3/4] install")
                let installCode = await forward("xcrun", ["simctl", "install", udid, app.path], nil, nil, continuation)
                if installCode != 0 { err("✗ install falhou (\(installCode))"); finish(installCode); return }

                // 5. Lançar.
                info("▸ [4/4] launch \(bundleID)")
                let launchCode = await forward("xcrun", ["simctl", "launch", udid, bundleID], nil, nil, continuation)
                finish(launchCode)
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// Roda um processo encaminhando suas linhas pro stream; devolve o exit-code.
    private func forward(
        _ executable: String, _ arguments: [String],
        _ cwd: URL?, _ env: [String: String]?,
        _ continuation: AsyncThrowingStream<ProcessEvent, Error>.Continuation
    ) async -> Int32 {
        var code: Int32 = -1
        do {
            for try await event in runner.stream(executable, arguments: arguments, workingDirectory: cwd, environment: env) {
                switch event {
                case .line(let line): continuation.yield(.line(line))
                case .metrics(let m): continuation.yield(.metrics(m))
                case .finished(let c): code = c
                }
                if Task.isCancelled { break }
            }
        } catch {
            continuation.yield(.line(LogLine(source: .stderr, text: "\(error)")))
        }
        return code
    }

    private func locateApp(in derivedData: URL) -> URL? {
        let products = derivedData.appendingPathComponent("Build/Products")
        let dirs = (try? fileManager.contentsOfDirectory(atPath: products.path)) ?? []
        guard let simDir = dirs.first(where: { $0.hasSuffix("-iphonesimulator") }) else { return nil }
        let configURL = products.appendingPathComponent(simDir)
        let entries = (try? fileManager.contentsOfDirectory(atPath: configURL.path)) ?? []
        guard let app = entries.first(where: { $0.hasSuffix(".app") }) else { return nil }
        return configURL.appendingPathComponent(app)
    }

    private func bundleIdentifier(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Info.plist")
        guard let data = fileManager.contents(atPath: plist.path),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }
}
