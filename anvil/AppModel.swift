import SwiftUI

/// Estado de build de uma trilha (iOS ou Android) de um projeto.
enum BuildStatus: Equatable {
    case idle
    case running
    case succeeded(seconds: Double)
    case failed(code: Int32)

    var label: String {
        switch self {
        case .idle: "—"
        case .running: "rodando…"
        case .succeeded(let s): String(format: "✓ %.1fs", s)
        case .failed(let code): "✗ código \(code)"
        }
    }

    var color: Color {
        switch self {
        case .idle: Forge.inkFaint
        case .running: Forge.warn
        case .succeeded: Forge.good
        case .failed: Forge.ember
        }
    }
}

/// Linha de log renderizável no console.
struct ConsoleLine: Identifiable {
    let id = UUID()
    let text: String
    let kind: Kind
    enum Kind { case info, stdout, stderr, ok, fail }
}

/// Uma amostra de consumo da build (CPU + memória) num instante.
struct MetricSample: Identifiable {
    let id = UUID()
    let cpu: Double      // % somado da árvore
    let memoryMB: Double
    let time: Date       // pra rolagem contínua no tempo
}

@MainActor
@Observable
final class AppModel {
    var projects: [Project] = []
    var selectedProjectID: Project.ID?

    // Inventário da máquina, carregado uma vez.
    var simulators: [Device] = []
    var emulators: [Device] = []
    var xcodes: [XcodeInstall] = []

    // Estado de build por componente.
    private(set) var status: [Component.ID: BuildStatus] = [:]
    private(set) var console: [Component.ID: [ConsoleLine]] = [:]
    private(set) var metrics: [Component.ID: [MetricSample]] = [:]
    private(set) var discovering: Set<Component.ID> = []   // descobrindo schemes/flavors
    private(set) var loadingInventory = false
    private var tasks: [Component.ID: Task<Void, Never>] = [:]

    /// Histórico recente de consumo (ring buffer ~ últimos N pontos).
    private let metricsWindow = 80

    let environments = ["debug", "staging", "prod"]

    private let store: ProjectStore
    private let detector = ProjectDetector()
    private let discovery = SchemeDiscovery()
    private let catalog = DeviceCatalog()
    private let buildRunner = BuildRunner()
    private let iosLauncher = IOSLauncher()

    init(store: ProjectStore? = nil) {
        self.store = store ?? ProjectStore()
    }

    var selectedProject: Project? {
        get { projects.first { $0.id == selectedProjectID } }
        set {
            guard let newValue, let idx = projects.firstIndex(where: { $0.id == newValue.id }) else { return }
            projects[idx] = newValue
        }
    }

    func status(_ component: Component) -> BuildStatus { status[component.id] ?? .idle }
    func console(_ component: Component) -> [ConsoleLine] { console[component.id] ?? [] }
    func metrics(_ component: Component) -> [MetricSample] { metrics[component.id] ?? [] }
    func isDiscovering(_ component: Component) -> Bool { discovering.contains(component.id) }

    // MARK: Ciclo de vida

    func bootstrap() async {
        do { projects = try store.load() } catch { projects = [] }
        if selectedProjectID == nil { selectedProjectID = projects.first?.id }
        await refreshInventory()
    }

    func refreshInventory() async {
        loadingInventory = true
        async let sims = (try? await catalog.iosSimulators()) ?? []
        async let avds = (try? await catalog.androidEmulators()) ?? []
        async let xc = (try? await catalog.xcodeInstalls()) ?? []
        simulators = await sims
        emulators = await avds
        xcodes = await xc
        loadingInventory = false
    }

    private func persist() {
        try? store.save(projects)
    }

    // MARK: Projetos

    /// Cria um projeto vazio (container nomeado) e o seleciona.
    func createProject(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(name: trimmed.isEmpty ? "novo projeto" : trimmed)
        projects.append(project)
        selectedProjectID = project.id
        persist()
    }

    func removeProject(_ project: Project) {
        for component in project.components { tasks[component.id]?.cancel() }
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id { selectedProjectID = projects.first?.id }
        persist()
    }

    /// Adiciona uma pasta como componente(s) do projeto (uma por plataforma detectada).
    func addComponent(to project: Project, at url: URL) async {
        guard let kinds = try? detector.detect(at: url),
              projects.contains(where: { $0.id == project.id })
        else { return }
        let baseName = detector.suggestedName(for: url)

        for platform in kinds {
            // 1) Aparece imediatamente com os defaults rápidos.
            var component = Component(name: baseName, path: url, platform: platform)
            switch platform {
            case .ios:
                component.selection.iosSimulator = simulators.first?.identifier
                component.selection.iosXcode = xcodes.first?.path
                component.selection.iosEnvironment = environments.first
            case .android:
                component.selection.androidEmulator = emulators.first?.identifier
                component.selection.androidEnvironment = environments.first
            case .bun, .docker:
                break
            }
            guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
            projects[idx].components.append(component)
            let id = component.id
            discovering.insert(id)
            persist()

            // 2) Descoberta lenta — UI mostra "descobrindo".
            switch platform {
            case .ios:
                let schemes = (try? await discovery.discoverSchemes(in: url)) ?? []
                mutateComponent(id) { $0.iosTargets = schemes; $0.selection.iosScheme = schemes.first?.name }
            case .android:
                let flavors = (try? await discovery.discoverFlavors(in: url)) ?? []
                mutateComponent(id) { $0.androidTargets = flavors; $0.selection.androidFlavor = flavors.first?.id }
            case .bun:
                let scripts = await discovery.discoverScripts(in: url)
                mutateComponent(id) { $0.tasks = scripts; $0.selection.task = scripts.first }
            case .docker:
                let services = await discovery.discoverDockerServices(in: url)
                // Padrão: nenhum serviço selecionado = stack inteiro (compose up).
                mutateComponent(id) { $0.tasks = services; $0.selection.task = nil }
            }
            discovering.remove(id)
            persist()
        }
    }

    /// Muta um componente por id (encontra projeto + componente).
    private func mutateComponent(_ id: Component.ID, _ mutate: (inout Component) -> Void) {
        for pi in projects.indices {
            if let ci = projects[pi].components.firstIndex(where: { $0.id == id }) {
                mutate(&projects[pi].components[ci]); return
            }
        }
    }

    func removeComponent(_ component: Component, from project: Project) {
        tasks[component.id]?.cancel()
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx].components.removeAll { $0.id == component.id }
        persist()
    }

    /// Atualiza a seleção de um componente e persiste.
    func updateSelection(_ component: Component, _ mutate: (inout Selection) -> Void) {
        for pi in projects.indices {
            if let ci = projects[pi].components.firstIndex(where: { $0.id == component.id }) {
                mutate(&projects[pi].components[ci].selection)
                persist()
                return
            }
        }
    }

    // MARK: Build

    /// Dispara build de todos os componentes de todos os projetos — em paralelo.
    func buildAll() {
        for project in projects {
            for component in project.components {
                build(component, mode: .build)
            }
        }
    }

    func build(_ component: Component, mode: BuildMode) {
        let key = component.id
        tasks[key]?.cancel()
        console[key] = []
        metrics[key] = []
        status[key] = .running

        let stream: AsyncThrowingStream<ProcessEvent, Error>

        // iOS Run = pipeline build → install → launch (via simctl).
        if component.platform == .ios && mode == .run {
            append(key, "▸ Run iOS — build · install · launch", .info)
            stream = iosLauncher.run(component: component, derivedData: derivedData(for: component))
        } else {
            let command: BuildCommand
            do {
                command = try buildRunner.command(for: component, mode: mode)
            } catch {
                append(key, "\(error)", .fail)
                status[key] = .failed(code: -1)
                return
            }
            append(key, "▸ \(command.display)", .info)
            stream = buildRunner.run(command)
        }

        tasks[key] = Task {
            let started = ContinuousClock.now
            let verb = (mode == .run) ? "Run" : "Build"
            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .line(let line):
                        self.append(key, line.text, line.source == .stderr ? .stderr : .stdout)
                    case .metrics(let m):
                        self.appendMetric(key, m)
                    case .finished(let code):
                        let secs = Double(started.duration(to: .now).components.seconds)
                        if code == 0 {
                            self.append(key, "✓ \(verb) concluído · \(String(format: "%.1f", secs))s", .ok)
                            self.status[key] = .succeeded(seconds: secs)
                        } else {
                            self.append(key, "✗ \(verb) falhou · código \(code)", .fail)
                            self.status[key] = .failed(code: code)
                        }
                    }
                }
            } catch {
                self.append(key, "\(error)", .fail)
                self.status[key] = .failed(code: -1)
            }
        }
    }

    /// DerivedData isolado por componente, pra localizar o `.app` do Run.
    private func derivedData(for component: Component) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Anvil/DerivedData/\(component.id.uuidString)", isDirectory: true)
    }

    func cancelBuild(_ component: Component) {
        let key = component.id
        tasks[key]?.cancel()
        if case .running = status[key] ?? .idle {
            append(key, "■ cancelado", .fail)
            status[key] = .failed(code: -1)
        }
    }

    private func append(_ key: Component.ID, _ text: String, _ kind: ConsoleLine.Kind) {
        console[key, default: []].append(ConsoleLine(text: text, kind: kind))
    }

    private func appendMetric(_ key: Component.ID, _ m: ProcessMetrics) {
        var series = metrics[key] ?? []
        series.append(MetricSample(cpu: m.cpu, memoryMB: m.memoryMB, time: Date()))
        if series.count > metricsWindow { series.removeFirst(series.count - metricsWindow) }
        metrics[key] = series
    }
}
