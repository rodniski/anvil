import SwiftUI
import UniformTypeIdentifiers

/// A prancha (landscape) de um projeto: bloco de título + componentes plugados.
struct ProjectBlueprint: View {
    let project: Project
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            BP.sheet.ignoresSafeArea()
            BlueprintGrid().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header.drawIn()
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 380, maximum: 380), spacing: 16, alignment: .top)],
                        alignment: .leading, spacing: 16
                    ) {
                        ForEach(Array(project.components.enumerated()), id: \.element.id) { index, component in
                            ComponentBlock(component: component, project: project, index: index + 1)
                                .drawIn(delay: 0.25 + Double(index) * 0.14)
                        }
                        AddComponentSlot(project: project)
                            .drawIn(delay: 0.25 + Double(project.components.count) * 0.14)
                    }
                    .padding(20)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                EditableTitle(
                    text: project.name, transform: { $0.uppercased() },
                    font: BP.display(42), color: BP.ink, tracking: 3
                ) { model.renameProject(project, to: $0) }
                Text("BUILD SPECIFICATION · \(project.components.count) COMPONENT\(project.components.count == 1 ? "" : "S")")
                    .font(BP.mono(10)).tracking(1).foregroundStyle(BP.inkDim)
            }
            Spacer()
            if !project.components.isEmpty {
                Button {
                    for component in project.components { model.build(component, mode: .build) }
                } label: {
                    Label("BUILD ALL", systemImage: "bolt.fill")
                }
                .buttonStyle(TechnicalButtonStyle(tint: BP.lineDim))
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BP.lineDim.opacity(0.25)).frame(height: 1).padding(.horizontal, 20)
        }
    }
}

/// Um componente do projeto — bloco autônomo com logo, specs, telemetria e
/// Build/Run próprios.
struct ComponentBlock: View {
    let component: Component
    let project: Project
    let index: Int
    @Environment(AppModel.self) private var model

    @State private var showConsole = false

    private var running: Bool { model.status(component) == .running }
    private var last: MetricSample? { model.metrics(component).last }

    private var discoverLabel: String {
        switch component.platform {
        case .ios: "DESCOBRINDO SCHEMES…"
        case .android: "DESCOBRINDO FLAVORS…"
        case .bun: "DESCOBRINDO SCRIPTS…"
        case .docker: "DESCOBRINDO SERVIÇOS…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                Text("Fig. \(index) — ")
                    .font(BP.serifItalic(18)).foregroundStyle(BP.ink)
                EditableTitle(
                    text: component.cardTitle,
                    font: BP.serifItalic(18), color: BP.ink
                ) { model.renameComponent(component, to: $0) }
                Spacer(minLength: 8)
                StatusBadge(status: model.status(component))
            }

            ComponentGlyph(platform: component.platform)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .opacity(model.isDiscovering(component) ? 0.5 : 1)

            if model.isDiscovering(component) {
                // Estado de loading: descobrindo schemes/flavors/scripts/serviços.
                BlueprintLoader(label: discoverLabel)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    switch component.platform {
                    case .ios: iosSelectors
                    case .android: androidSelectors
                    case .bun: bunSelectors
                    case .docker: dockerSelectors
                    }
                }

                BuildWaveView(samples: model.metrics(component), live: running)
                    .frame(height: 46)
                HStack {
                    Text("CPU \(Int(last?.cpu ?? 0))%").font(BP.mono(11)).foregroundStyle(BP.inkFaint)
                    Spacer()
                    Text(last.map { "\(Int($0.memoryMB)) MB" } ?? "—").font(BP.mono(11)).foregroundStyle(BP.inkFaint)
                }

                HStack(spacing: 8) {
                    Button("BUILD") { model.build(component, mode: .build) }
                        .buttonStyle(TechnicalButtonStyle(tint: BP.line)).disabled(running)
                    Button("RUN") { model.build(component, mode: .run) }
                        .buttonStyle(TechnicalButtonStyle(tint: BP.lineDim)).disabled(running)
                    if running {
                        Button("STOP") { model.cancelBuild(component) }
                            .buttonStyle(TechnicalButtonStyle(tint: BP.accent))
                    }
                    Spacer()
                    Button(role: .destructive) { model.removeComponent(component, from: project) } label: {
                        Image(systemName: "trash").font(.system(size: 13))
                    }
                    .buttonStyle(TechnicalButtonStyle(tint: Color(hex: 0xFF6B6B)))
                    .help("Excluir componente")
                }

                consoleSection
            }
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
        .doubleBorder(running ? BP.accent.opacity(0.8) : BP.lineDim.opacity(0.7))
    }

    // MARK: Selectors

    @ViewBuilder private var iosSelectors: some View {
        selector("scheme", \.iosScheme, component.iosTargets.map { ($0.name, $0.name) })
        selector("target", \.iosSimulator, model.simulators.map { ($0.identifier, deviceLabel($0)) }, loading: model.loadingInventory)
        selector("xcode", \.iosXcode, model.xcodes.map { ($0.path, $0.version) }, loading: model.loadingInventory)
    }
    @ViewBuilder private var androidSelectors: some View {
        selector("flavor", \.androidFlavor, component.androidTargets.map { ($0.id, $0.displayName) })
        selector("device", \.androidEmulator, model.emulators.map { ($0.identifier, $0.name) }, loading: model.loadingInventory)
        selector("env", \.androidEnvironment, model.environments.map { ($0, $0) })
    }
    @ViewBuilder private var bunSelectors: some View {
        selector("script", \.task, component.tasks.map { ($0, $0) })
        selector("env", \.environment, model.environments.map { ($0, $0) })
        // Bun/Docker têm 2 seletores; iOS/Android têm 3. Reserva a linha que
        // falta pra todos os cards terem a mesma altura.
        selectorPlaceholder()
    }
    @ViewBuilder private var dockerSelectors: some View {
        // "" = todos os serviços (sobe o stack inteiro).
        selector("service", \.task, [("", "— todos os serviços —")] + component.tasks.map { ($0, $0) })
        selector("env", \.environment, model.environments.map { ($0, $0) })
        selectorPlaceholder()
    }

    /// Linha invisível com o mesmo layout de um seletor — ocupa espaço no
    /// layout (mantém a altura) sem desenhar nada nem receber interação.
    @ViewBuilder private func selectorPlaceholder() -> some View {
        HStack(spacing: 12) {
            Text(" ").font(BP.mono(12)).frame(width: 58, alignment: .leading)
            BlueprintDropdown(selection: .constant(""), options: [])
        }
        .hidden()
    }

    @ViewBuilder
    private func selector(_ label: String, _ keyPath: WritableKeyPath<Selection, String?>,
                          _ options: [(value: String, label: String)], loading: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label).font(BP.mono(12)).foregroundStyle(BP.inkFaint)
                .frame(width: 58, alignment: .leading)
            BlueprintDropdown(selection: pick(keyPath), options: options, loading: loading)
        }
    }

    private func deviceLabel(_ d: Device) -> String {
        if let r = d.runtime { "\(d.name) · \(r)" } else { d.name }
    }

    private func pick(_ keyPath: WritableKeyPath<Selection, String?>) -> Binding<String> {
        Binding(
            get: { component.selection[keyPath: keyPath] ?? "" },
            set: { v in model.updateSelection(component) { $0[keyPath: keyPath] = v.isEmpty ? nil : v } }
        )
    }

    // MARK: Console (log do build, retrátil — abre sozinho ao rodar)

    @ViewBuilder private var consoleSection: some View {
        let log = model.console(component)
        let open = showConsole || running
        VStack(spacing: 0) {
            Button { withAnimation { showConsole.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                    Text("console").font(BP.mono(10)).tracking(1.5)
                    if let last = log.last, !open {
                        Text(last.text).font(BP.mono(10)).foregroundStyle(BP.inkFaint.opacity(0.7))
                            .lineLimit(1).truncationMode(.head)
                    }
                    Spacer()
                }
                .foregroundStyle(BP.inkFaint)
                .padding(.top, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                ComponentConsole(lines: log).frame(height: 150).padding(.top, 8)
            }
        }
    }
}

/// Título que vira campo de texto ao receber duplo-clique — pra renomear
/// projeto/card no lugar. Enter confirma, Esc cancela, vazio volta ao padrão.
struct EditableTitle: View {
    let text: String
    var transform: (String) -> String = { $0 }
    let font: Font
    let color: Color
    var tracking: CGFloat = 0
    let onCommit: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("nome", text: $draft)
                .textFieldStyle(.plain)
                .font(font).foregroundStyle(color).tracking(tracking)
                .fixedSize()
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit { commit() }
                .onExitCommand { editing = false }
                .onChange(of: focused) { _, now in if !now { commit() } }
        } else {
            Text(transform(text))
                .font(font).foregroundStyle(color).tracking(tracking)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { draft = text; editing = true }
                .help("Duplo-clique para renomear")
        }
    }

    private func commit() {
        guard editing else { return }   // evita disparo duplo (onSubmit + perda de foco)
        editing = false
        onCommit(draft)
    }
}

/// Painel de log de um componente — mono, escuro, cores por origem.
struct ComponentConsole: View {
    let lines: [ConsoleLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(BP.mono(10.5))
                            .foregroundStyle(color(line.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    if lines.isEmpty {
                        Text("sem saída ainda — dispare um build.")
                            .font(BP.mono(10.5)).foregroundStyle(BP.inkFaint)
                    }
                }
                .padding(10)
            }
            .onChange(of: lines.count) {
                if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .background(Color.black.opacity(0.3))
        .overlay(Rectangle().strokeBorder(BP.lineDim.opacity(0.3), lineWidth: 1))
    }

    private func color(_ kind: ConsoleLine.Kind) -> Color {
        switch kind {
        case .info: BP.lineDim
        case .stdout: BP.inkDim
        case .stderr: BP.accentSoft
        case .ok: Color(hex: 0x7FE0A8)
        case .fail: Color(hex: 0xFF6B6B)
        }
    }
}

/// Slot tracejado pra adicionar um componente (abre o folder picker).
struct AddComponentSlot: View {
    let project: Project
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        Button { importing = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 20, weight: .light))
                Text("Adicionar\ncomponente").font(BP.mono(12)).multilineTextAlignment(.center)
            }
            .foregroundStyle(BP.lineDim)
            .frame(width: 380, height: 200)
            .contentShape(Rectangle())
            .overlay(Rectangle().strokeBorder(BP.lineDim.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
        }
        .buttonStyle(.plain)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            Task {
                await model.addComponent(to: project, at: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
    }
}

/// Desenho técnico que se traça (plotter) ao aparecer.
struct TracedDrawing: View {
    let shape: AnyShape
    var duration: Double = 1.1
    var lineWidth: CGFloat = 1.4
    @State private var progress: CGFloat = 0

    var body: some View {
        shape
            .trim(from: 0, to: progress)
            .stroke(BP.line, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                progress = 0
                withAnimation(.easeInOut(duration: duration)) { progress = 1 }
            }
    }
}

// MARK: - Glyph do componente (logo real + cantos traçados)

/// O logo da plataforma sobre cantos técnicos que se traçam (plotter).
struct ComponentGlyph: View {
    let platform: Platform
    @State private var shown = false

    private var asset: String { platform.logoAsset }
    // Apple é monocromático → branco. Os demais ficam na cor original (senão
    // o template achata e some com olhos/carinha).
    private var tintWhite: Bool { platform == .ios }

    var body: some View {
        ZStack {
            TracedDrawing(shape: AnyShape(BracketShape()))
            Image(asset)
                .renderingMode(tintWhite ? .template : .original)
                .resizable().scaledToFit()
                .foregroundStyle(BP.line)
                .padding(24)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.9)
                .onAppear {
                    shown = false
                    withAnimation(.easeOut(duration: 0.5).delay(0.6)) { shown = true }
                }
        }
    }
}

/// Cantos de registro (estilo prancha) — quatro "L" nas extremidades.
struct BracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: 4, dy: 4)
        let l: CGFloat = 15
        // TL
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // TR
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // BR
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // BL
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// Bigorna técnica vetorial (perfil) — silhueta + arestas + hachura.
/// É um `Path` de verdade, então o `.trim` a desenha linha a linha.
struct AnvilShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()

        // Silhueta (sentido horário a partir da ponta do horn).
        let outline: [(CGFloat, CGFloat)] = [
            (0.03, 0.40), (0.24, 0.30), (0.92, 0.30), (0.92, 0.41),
            (0.72, 0.44), (0.62, 0.62), (0.60, 0.76), (0.72, 0.90),
            (0.80, 0.94), (0.80, 1.00), (0.20, 1.00), (0.20, 0.94),
            (0.28, 0.90), (0.40, 0.76), (0.38, 0.62), (0.28, 0.44), (0.24, 0.44),
        ]
        p.move(to: pt(outline[0].0, outline[0].1))
        for c in outline.dropFirst() { p.addLine(to: pt(c.0, c.1)) }
        p.closeSubpath()

        // Aresta frontal da face (o "degrau" sob o topo).
        p.move(to: pt(0.24, 0.44)); p.addLine(to: pt(0.72, 0.44))
        // Aresta superior interna (espessura do topo).
        p.move(to: pt(0.24, 0.30)); p.addLine(to: pt(0.24, 0.44))

        // Furo hardy (quadradinho no topo, à direita).
        p.move(to: pt(0.78, 0.325)); p.addLine(to: pt(0.85, 0.325))
        p.addLine(to: pt(0.85, 0.355)); p.addLine(to: pt(0.78, 0.355)); p.closeSubpath()

        // Hachura no corpo (sombreamento técnico).
        for x in stride(from: CGFloat(0.34), through: 0.56, by: 0.055) {
            p.move(to: pt(x, 0.47)); p.addLine(to: pt(x, 0.60))
        }
        return p
    }
}
