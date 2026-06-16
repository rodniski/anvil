import SwiftUI
import AppKit

@main
struct AnvilApp: App {
    @State private var model = AppModel()

    init() { FontRegistry.register() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 560)
                .preferredColorScheme(.dark)
                .task { await model.bootstrap() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // sem "New Window"
        }

        // Ícone na barra de menus do macOS + atalhos rápidos.
        MenuBarExtra {
            MenuBarContent().environment(model)
        } label: {
            Image("AnvilGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Conteúdo do menu da barra de status: ações rápidas de build.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Abrir Anvil") {
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("0", modifiers: [.command, .shift])

        Divider()

        Button("Build em todos os projetos") { model.buildAll() }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(model.projects.allSatisfy { $0.components.isEmpty })

        // Cada projeto vira uma seção (título + separadores) com as ações
        // direto na lista — sem submenu pra abrir.
        ForEach(model.projects) { project in
            Section(project.name) {
                Button("Build todos os componentes") {
                    for c in project.components { model.build(c, mode: .build) }
                }
                .disabled(project.components.isEmpty)

                ForEach(project.components) { component in
                    Button("Build \(component.name) · \(component.platform.rawValue)") {
                        model.build(component, mode: .build)
                    }
                }
            }
        }

        Divider()
        Button("Sair") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
