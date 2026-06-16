import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedProjectID) {
                // Título da seção só aparece quando há projetos — no empty
                // state a sidebar fica limpa, sem o "m4labs" órfão.
                if !model.projects.isEmpty {
                    Section("m4labs") {
                        ForEach(model.projects) { project in
                            Label(project.name, systemImage: "square.stack.3d.up")
                                .tag(project.id)
                                .contextMenu {
                                    Button("Excluir projeto", role: .destructive) {
                                        model.removeProject(project)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Projects")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            .safeAreaInset(edge: .bottom) {
                Button { startCreate() } label: {
                    Label("projeto", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(TechnicalButtonStyle(tint: BP.lineDim))
                .padding(10)
            }
        } detail: {
            if let project = model.selectedProject {
                ProjectBlueprint(project: project).id(project.id)
            } else {
                EmptyStateView(name: $newName) {
                    let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !n.isEmpty else { return }
                    model.createProject(name: n)
                    newName = ""
                }
            }
        }
        .tint(BP.accent)
        .sheet(isPresented: $creating) {
            CreateProjectSheet(name: $newName) {
                model.createProject(name: newName)
                creating = false
            } onCancel: { creating = false }
        }
    }

    private func startCreate() { newName = ""; creating = true }
}

/// Sheet de criar projeto — só o nome (o projeto é um container).
struct CreateProjectSheet: View {
    @Binding var name: String
    var onCreate: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Novo projeto").font(BP.serif(20)).foregroundStyle(BP.ink)
            Text("Um projeto agrupa componentes (Swift, Kotlin, Bun, Docker…). Você adiciona as pastas depois, dentro dele.")
                .font(.callout).foregroundStyle(BP.inkDim)
            TextField("nome do projeto", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Criar", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(BP.bg)
        .preferredColorScheme(.dark)
    }

    private func submit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onCreate()
    }
}

/// Tela vazia — dois painéis: patente à esquerda, criação de projeto à direita.
struct EmptyStateView: View {
    @Binding var name: String
    var onCreate: () -> Void

    @State private var appeared = false

    // Tamanho de design fixo — escalado pra caber em qualquer janela (responsivo).
    private let designW: CGFloat = 1108
    private let designH: CGFloat = 600

    var body: some View {
        GeometryReader { geo in
            // Só reduz (nunca amplia) — ampliar com scaleEffect borraria o texto.
            let k = max(0.5, min(1.0, min(geo.size.width / (designW + 96),
                                          geo.size.height / (designH + 96))))
            ZStack {
                BP.sheet.ignoresSafeArea()
                BlueprintGrid().ignoresSafeArea()

                HStack(spacing: 28) {
                    anvilCard
                    createCard
                }
                .frame(width: designW, height: designH)
                .scaleEffect(k)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
    }

    // Esquerda — a peça em exibição: título + patente vetorial se desenhando.
    private var anvilCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ANVIL").font(BP.display(44)).tracking(4).foregroundStyle(BP.ink)
                Spacer()
                Text("PLATE 1").font(BP.mono(13)).tracking(2).foregroundStyle(BP.lineDim)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 18)
            .overlay(alignment: .bottom) { Rectangle().fill(BP.lineDim.opacity(0.22)).frame(height: 1) }

            EtchReveal(resource: "AnvilPatentVector", duration: 2.4)
                .padding(42)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("ANVIL & SWAGE · PAT. 405,191 · 1889")
                .font(BP.mono(12)).tracking(1).foregroundStyle(BP.inkFaint)
                .padding(.bottom, 22)
        }
        .frame(width: 540, height: 600)
        .doubleBorder(BP.line.opacity(0.5))
    }

    // Direita — bloco de criação, conteúdo centralizado verticalmente.
    private var createCard: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 22) {
                Text("NEW PROJECT").font(BP.mono(13)).tracking(2.5).foregroundStyle(BP.lineDim)
                Text("Nova prancha").font(BP.serif(50)).foregroundStyle(BP.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Um projeto agrupa componentes (Swift, Kotlin, Bun, Docker…). Crie o container e adicione as pastas dentro.")
                    .font(BP.mono(16)).foregroundStyle(BP.inkDim).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("nome do projeto").font(BP.mono(13)).foregroundStyle(BP.inkFaint)
                    TextField("ex.: m4doc", text: $name)
                        .textFieldStyle(.plain)
                        .font(BP.mono(22)).foregroundStyle(BP.ink)
                        .padding(.vertical, 14).padding(.horizontal, 16)
                        .background(BP.line.opacity(0.05))
                        .overlay(Rectangle().strokeBorder(BP.lineDim.opacity(0.4), lineWidth: 1))
                        .onSubmit(onCreate)
                }
                .padding(.top, 8)

                Button(action: onCreate) {
                    Label("Criar projeto", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(TechnicalButtonStyle(kind: .prominent, tint: BP.line, fontSize: 18))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer(minLength: 0)
        }
        .padding(44)
        .frame(width: 540, height: 600)
        .doubleBorder(BP.line.opacity(0.5))
    }
}


/// Botão técnico do blueprint — linha fina é a linguagem aqui, não enfeite.
/// `.ghost` = contorno; `.prominent` = preenchido (ação primária).
struct TechnicalButtonStyle: ButtonStyle {
    enum Kind { case ghost, prominent }
    var kind: Kind = .ghost
    var tint: Color = Forge.steel
    var fontSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill: Color = kind == .prominent
            ? tint.opacity(pressed ? 0.75 : 1)
            : tint.opacity(pressed ? 0.85 : 0.07)
        let label: Color = (kind == .prominent || pressed) ? .black : tint

        return configuration.label
            .font(BP.mono(fontSize, weight: .medium))
            .foregroundStyle(label)
            .padding(.vertical, fontSize * 0.55).padding(.horizontal, fontSize * 1.25)
            .background(RoundedRectangle(cornerRadius: 5).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(tint.opacity(kind == .prominent ? 0 : 0.7))
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}
