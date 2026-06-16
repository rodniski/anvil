import SwiftUI

/// Badge de status compacto.
struct StatusBadge: View {
    let status: BuildStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(BP.mono(11)).tracking(0.5).foregroundStyle(color)
        }
    }

    private var label: String {
        switch status {
        case .idle: "idle"
        case .running: "compiling"
        case .succeeded: "ready"
        case .failed: "failed"
        }
    }
    private var color: Color {
        switch status {
        case .idle: BP.inkFaint
        case .running: BP.accent
        case .succeeded: Color(hex: 0x7FE0A8)
        case .failed: Color(hex: 0xFF6B6B)
        }
    }
}

/// Dropdown blueprint — campo técnico de linha fina, mono, reto.
/// `loading` = inventário ainda carregando → mostra "carregando…" pulsando.
struct BlueprintDropdown: View {
    @Binding var selection: String
    let options: [(value: String, label: String)]
    var loading: Bool = false

    @State private var pulse = false
    @State private var open = false
    private var isLoading: Bool { loading && options.isEmpty }

    private var currentLabel: String {
        if isLoading { return "carregando…" }
        return options.first { $0.value == selection }?.label ?? (options.isEmpty ? "n/a" : "—")
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(BP.mono(12))
                    .foregroundStyle(options.isEmpty ? BP.inkFaint : BP.ink)
                    .lineLimit(1).truncationMode(.middle)
                    .opacity(isLoading && pulse ? 0.45 : 1)
                Spacer(minLength: 6)
                Image(systemName: isLoading ? "ellipsis" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isLoading ? BP.lineDim : BP.line.opacity(0.85))
                    .opacity(isLoading && pulse ? 0.45 : 1)
            }
            .padding(.vertical, 7).padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BP.line.opacity(0.05))
            .overlay(Rectangle().strokeBorder(BP.line.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(options.isEmpty)
        .onChange(of: isLoading, initial: true) { _, now in
            pulse = false
            if now { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
        }
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.value) { idx, option in
                        if idx > 0 { Rectangle().fill(BP.lineDim.opacity(0.12)).frame(height: 1) }
                        DropdownRow(label: option.label, selected: option.value == selection) {
                            selection = option.value; open = false
                        }
                    }
                }
                .padding(.vertical, 5)
            }
            .scrollContentBackground(.hidden)
            .frame(width: 300)
            .frame(maxHeight: 340)
            .background(BP.bg)
            .preferredColorScheme(.dark)
        }
    }
}

/// Uma opção do dropdown custom (linha com hover, no estilo da prancha).
private struct DropdownRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(BP.mono(12.5))
                    .foregroundStyle(selected ? BP.line : BP.inkDim)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(BP.accent)
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? BP.line.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// A onda: consumo da build como banda espelhada (cianótipo branco). Sempre viva;
/// engrena quando os dados chegam. `live` rola no tempo (osciloscópio).
struct BuildWaveView: View {
    let samples: [MetricSample]
    var live: Bool = true

    private let window: TimeInterval = 14
    private let renderDelay: TimeInterval = 1.3
    private let columns = 60

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { ctx, size in draw(ctx, size, now: timeline.date) }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, now: Date) {
        let center = size.height / 2
        let maxAmp = size.height / 2 - 3
        let t = now.timeIntervalSinceReferenceDate
        let hasData = samples.count > 1
        let renderTime = now.addingTimeInterval(-renderDelay)

        var top: [CGPoint] = []
        var bot: [CGPoint] = []
        for j in 0...columns {
            let fx = Double(j) / Double(columns)
            let x = size.width * fx
            let ripple = maxAmp * 0.10 * (0.55 + 0.45 * sin(fx * 22 + t * 2.4))
            var amp = ripple
            if hasData {
                let time = live
                    ? renderTime.addingTimeInterval(-(1 - fx) * window)
                    : sampleTime(atFraction: fx)
                amp = ripple * 0.4 + maxAmp * CGFloat(min(1, cpuAt(time) / 100)) * 0.94
            }
            top.append(CGPoint(x: x, y: center - amp))
            bot.append(CGPoint(x: x, y: center + amp))
        }

        var fill = Path()
        fill.move(to: top[0])
        for p in top.dropFirst() { fill.addLine(to: p) }
        for p in bot.reversed() { fill.addLine(to: p) }
        fill.closeSubpath()
        ctx.fill(fill, with: .color(BP.line.opacity(0.10)))

        let style = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
        ctx.stroke(smoothed(top), with: .color(BP.line.opacity(0.9)), style: style)
        ctx.stroke(smoothed(bot), with: .color(BP.line.opacity(0.9)), style: style)
    }

    private func sampleTime(atFraction fx: Double) -> Date {
        guard let first = samples.first, let last = samples.last else { return Date() }
        return first.time.addingTimeInterval(fx * last.time.timeIntervalSince(first.time))
    }

    private func cpuAt(_ time: Date) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if time <= first.time { return first.cpu }
        if time >= last.time { return last.cpu }
        for i in 1 ..< samples.count where samples[i].time >= time {
            let a = samples[i - 1], b = samples[i]
            let span = b.time.timeIntervalSince(a.time)
            let f = span > 0 ? time.timeIntervalSince(a.time) / span : 0
            return a.cpu + (b.cpu - a.cpu) * f
        }
        return last.cpu
    }

    private func smoothed(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard let first = p.first else { return path }
        path.move(to: first)
        if p.count < 3 { for pt in p.dropFirst() { path.addLine(to: pt) }; return path }
        for i in 1 ..< p.count - 1 {
            let mid = CGPoint(x: (p[i].x + p[i + 1].x) / 2, y: (p[i].y + p[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: p[i])
        }
        path.addLine(to: p[p.count - 1])
        return path
    }
}
