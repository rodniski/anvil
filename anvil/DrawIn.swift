import SwiftUI

/// Faz qualquer view "surgir desenhada": uma varredura (máscara) revela o
/// conteúdo da esquerda pra direita, como um plotter passando a caneta.
/// Use `.drawIn(delay:)` e escalone os delays pra montar a tela em sequência.
struct DrawIn: ViewModifier {
    var delay: Double = 0
    var duration: Double = 0.55
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * progress)
                }
            }
            .onAppear {
                progress = 0
                withAnimation(.easeInOut(duration: duration).delay(delay)) { progress = 1 }
            }
    }
}

extension View {
    func drawIn(delay: Double = 0, duration: Double = 0.55) -> some View {
        modifier(DrawIn(delay: delay, duration: duration))
    }
}

/// Moldura técnica de **linha dupla** (duas bordas concêntricas), como nas
/// pranchas de engenharia. A interna é levemente mais fina/discreta.
struct DoubleBorder: ViewModifier {
    var color: Color
    var lineWidth: CGFloat = 1
    var gap: CGFloat = 5

    func body(content: Content) -> some View {
        content
            .overlay(Rectangle().strokeBorder(color, lineWidth: lineWidth))
            .overlay(Rectangle().strokeBorder(color.opacity(0.55), lineWidth: lineWidth).padding(gap))
    }
}

extension View {
    func doubleBorder(_ color: Color = BP.lineDim.opacity(0.7), lineWidth: CGFloat = 1, gap: CGFloat = 5) -> some View {
        modifier(DoubleBorder(color: color, lineWidth: lineWidth, gap: gap))
    }
}

/// Indicador indeterminado estilo plotter — um segmento varrendo num trilho.
struct BlueprintLoader: View {
    var label: String
    var color: Color = BP.accent

    var body: some View {
        VStack(spacing: 9) {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let w = geo.size.width
                    let seg = w * 0.32
                    let x = (sin(t * 2.0) * 0.5 + 0.5) * max(0, w - seg)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(BP.lineDim.opacity(0.2)).frame(height: 2)
                        Rectangle().fill(color).frame(width: seg, height: 2).offset(x: x)
                    }
                    .frame(height: 2)
                }
                .frame(height: 2)
            }
            Text(label).font(BP.mono(11)).tracking(1.5).foregroundStyle(BP.lineDim)
        }
    }
}
