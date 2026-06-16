import SwiftUI

/// Parser mínimo de `d=""` de SVG → `Path` do SwiftUI.
/// Cobre M/L/H/V/C/S/Q/T/Z (absoluto e relativo) — o suficiente pra saída de
/// vetorizadores (potrace/vtracer).
enum SVGPath {
    static func path(from d: String) -> Path {
        var path = Path()
        let ch = Array(d)
        let n = ch.count
        var i = 0
        var current = CGPoint.zero
        var startPt = CGPoint.zero
        var lastCtrl: CGPoint?
        var cmd: Character = " "

        func skip() { while i < n, ch[i] == " " || ch[i] == "," || ch[i] == "\n" || ch[i] == "\t" || ch[i] == "\r" { i += 1 } }
        func number() -> CGFloat? {
            skip()
            var s = ""
            if i < n, ch[i] == "-" || ch[i] == "+" { s.append(ch[i]); i += 1 }
            var dot = false
            while i < n {
                let c = ch[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == ".", !dot { dot = true; s.append(c); i += 1 }
                else if c == "e" || c == "E" { s.append(c); i += 1; if i < n, ch[i] == "-" || ch[i] == "+" { s.append(ch[i]); i += 1 } }
                else { break }
            }
            return Double(s).map { CGFloat($0) }
        }
        func point(rel: Bool) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while i < n {
            skip()
            guard i < n else { break }
            if ch[i].isLetter { cmd = ch[i]; i += 1; skip() }
            let rel = cmd.isLowercase
            let before = i

            switch Character(cmd.uppercased()) {
            case "M":
                guard let p = point(rel: rel) else { break }
                path.move(to: p); current = p; startPt = p
                cmd = rel ? "l" : "L"   // pontos seguintes do M viram lineto
            case "L":
                guard let p = point(rel: rel) else { break }
                path.addLine(to: p); current = p
            case "H":
                guard let x = number() else { break }
                let p = CGPoint(x: rel ? current.x + x : x, y: current.y); path.addLine(to: p); current = p
            case "V":
                guard let y = number() else { break }
                let p = CGPoint(x: current.x, y: rel ? current.y + y : y); path.addLine(to: p); current = p
            case "C":
                guard let c1 = point(rel: rel), let c2 = point(rel: rel), let e = point(rel: rel) else { break }
                path.addCurve(to: e, control1: c1, control2: c2); lastCtrl = c2; current = e
            case "S":
                guard let c2 = point(rel: rel), let e = point(rel: rel) else { break }
                let c1 = lastCtrl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: e, control1: c1, control2: c2); lastCtrl = c2; current = e
            case "Q":
                guard let c1 = point(rel: rel), let e = point(rel: rel) else { break }
                path.addQuadCurve(to: e, control: c1); lastCtrl = c1; current = e
            case "T":
                guard let e = point(rel: rel) else { break }
                let c1 = lastCtrl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addQuadCurve(to: e, control: c1); lastCtrl = c1; current = e
            case "Z":
                path.closeSubpath(); current = startPt
            default:
                break
            }
            if i == before { i += 1 }   // anti-travamento
            if Character(cmd.uppercased()) != "C", Character(cmd.uppercased()) != "S",
               Character(cmd.uppercased()) != "Q", Character(cmd.uppercased()) != "T" { lastCtrl = nil }
        }
        return path
    }
}

/// Arte vetorial carregada de um SVG (paths combinados + tamanho).
struct SVGArt {
    let combined: Path
    let size: CGSize

    private static var cache: [String: SVGArt] = [:]

    static func load(_ name: String) -> SVGArt {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let svg = try? String(contentsOf: url, encoding: .utf8)
        else { return SVGArt(combined: Path(), size: .zero) }

        var size = CGSize(width: 664, height: 682)
        if let vb = try? NSRegularExpression(pattern: "viewBox=\"0 0 ([0-9.]+) ([0-9.]+)\""),
           let m = vb.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
           let wR = Range(m.range(at: 1), in: svg), let hR = Range(m.range(at: 2), in: svg),
           let w = Double(svg[wR]), let h = Double(svg[hR]) {
            size = CGSize(width: w, height: h)
        }

        var entries: [(Path, CGFloat)] = []
        if let re = try? NSRegularExpression(pattern: "\\sd=\"([^\"]*)\"") {
            re.enumerateMatches(in: svg, range: NSRange(svg.startIndex..., in: svg)) { match, _, _ in
                guard let match, let r = Range(match.range(at: 1), in: svg) else { return }
                let path = SVGPath.path(from: String(svg[r]))
                entries.append((path, path.boundingRect.midX))
            }
        }
        // Ordena por X (varre esquerda→direita) e combina num só Path.
        var combined = Path()
        for (path, _) in entries.sorted(by: { $0.1 < $1.1 }) { combined.addPath(path) }

        let art = SVGArt(combined: combined, size: size)
        cache[name] = art
        return art
    }
}

/// Traça a arte como uma **caneta percorrendo o path** (stroke + trim): o traço
/// cresce ao longo do comprimento de cada subpath, em sequência.
struct EtchReveal: View {
    let resource: String
    var duration: Double = 2.4
    var lineWidth: CGFloat = 1.0
    var color: Color = BP.line

    @State private var progress: CGFloat = 0

    var body: some View {
        let art = SVGArt.load(resource)
        TraceShape(source: art.combined, size: art.size, progress: progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                progress = 0
                withAnimation(.easeInOut(duration: duration)) { progress = 1 }
            }
    }
}

/// Escala o path pra caber no rect e devolve o trecho traçado até `progress`.
private struct TraceShape: Shape {
    let source: Path
    let size: CGSize
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard size.width > 0, size.height > 0 else { return Path() }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let ox = (rect.width - size.width * scale) / 2
        let oy = (rect.height - size.height * scale) / 2
        let t = CGAffineTransform.identity.translatedBy(x: ox, y: oy).scaledBy(x: scale, y: scale)
        return source.applying(t).trimmedPath(from: 0, to: progress)
    }
}
