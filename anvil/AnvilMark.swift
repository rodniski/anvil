import SwiftUI

/// A malha técnica viva (Metal shader `blueprint`), full-bleed atrás do empty state.
struct BlueprintField: View {
    var heat: Double = 0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        ShaderLibrary.blueprint(
                            .float(Float(t.truncatingRemainder(dividingBy: 1000))),
                            .float2(Float(geo.size.width), Float(geo.size.height)),
                            .float(Float(heat))
                        )
                    )
            }
        }
        .animation(.easeOut(duration: 0.4), value: heat)
    }
}

/// Malha cianótipo (papel milimetrado) — fundo da prancha, sem custo de GPU.
struct BlueprintGrid: View {
    var spacing: CGFloat = 20

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            ctx.stroke(path, with: .color(BP.grid), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// A bigorna em linha técnica (o logo line-art), tintada molten com glow sutil.
struct AnvilLine: View {
    var heat: Double = 0

    var body: some View {
        Image("Anvil")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(
                LinearGradient(
                    colors: [Forge.molten, Forge.ember],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .shadow(color: Forge.molten.opacity(0.5 + heat * 0.4), radius: 8 + heat * 12)
            .animation(.easeOut(duration: 0.4), value: heat)
    }
}
