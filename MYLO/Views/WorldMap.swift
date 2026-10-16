import UIKit
import SwiftUI

/// World map (image asset "WorldMapImage") with the server country marked and named.
/// - idle: the whole map, the selected country marked and named
/// - connecting: a plane takes off from Iran and flies slowly to the country while the camera zooms in
/// - connected: zoomed on the country with a pulsing marker; disconnecting zooms back out
struct WorldMap: View {
    var cc: String?
    var connected: Bool
    var connecting: Bool = false
    /// Country codes of all servers; each one is named on its country when there is room for the text.
    var labelCodes: [String] = []

    @State private var startAt: Date? = nil     // when the current flight started (nil while active = already there)
    @State private var endAt: Date? = nil       // when we went back to idle
    @State private var pEnd: Double = 0         // flight progress at that moment (for the zoom-out)
    @State private var animatingOut = false

    /// Size of the map image in pixels. The card must have this aspect ratio (see HomeView).
    static let imageSize = CGSize(width: 1586, height: 787)
    private static let flightTime = 4.6         // seconds, plane take-off to arrival
    private static let outTime = 0.9            // seconds, zoom back out

    private var active: Bool { connected || connecting }

    /// Countries whose name is already printed in the picture (the extra label fades out when zoomed in).
    private static let printed: Set<String> = ["US", "CA", "MX", "BR", "GB", "DE", "FR", "ES", "TR", "EG", "SA", "IN",
                                                "CN", "JP", "RU", "KZ", "AU", "NZ", "ZA", "AR"]

    // MARK: geometry

    /// Latitude/longitude -> pixel in the map image (Miller projection fitted to the artwork).
    static func point(lat: Double, lon: Double) -> CGPoint {
        let r = lat * Double.pi / 180
        let x = 247.95 * (lon * Double.pi / 180) + 760.6
        let y = 523.29 - 268.69 * 1.25 * log(tan(Double.pi / 4 + 0.4 * r))
        return CGPoint(x: x, y: y)
    }

    private static func point(_ cc: String?) -> CGPoint? {
        guard let g = Geo.latLon(cc) else { return nil }
        return point(lat: g.lat, lon: g.lon)
    }

    private static func zoomMax(_ cc: String?) -> CGFloat {
        switch (cc ?? "").uppercased() {
        case "RU": return 1.7
        case "CN", "US", "CA", "BR", "AU": return 1.9
        case "IN", "AR", "KZ", "MX", "SA", "ID", "CL": return 2.3
        case "SG", "HK", "LU", "BN", "AE", "IL": return 3.8
        default: return 3.0
        }
    }

    private static func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

    // MARK: view

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(active || animatingOut))) { tl in
            Canvas { ctx, size in
                draw(&ctx, size, tl.date)
            }
        }
        .onValueChange(of: active) { on in
            if on {
                startAt = Date(); endAt = nil; animatingOut = false
            } else {
                let now = Date()
                pEnd = startAt.map { min(max(now.timeIntervalSince($0) / Self.flightTime, 0), 1) } ?? 1
                startAt = nil; endAt = now; animatingOut = true
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.outTime + 0.15) { animatingOut = false }
            }
        }
    }

    /// 0 = whole map, 1 = arrived and zoomed in.
    private func progress(_ now: Date) -> Double {
        if active {
            guard let s = startAt else { return 1 }
            return min(max(now.timeIntervalSince(s) / Self.flightTime, 0), 1)
        }
        guard let e = endAt else { return 0 }
        let q = min(max(now.timeIntervalSince(e) / Self.outTime, 0), 1)
        return pEnd * (1 - Self.smooth(q))
    }

    // MARK: drawing

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ now: Date) {
        let W = Self.imageSize.width, H = Self.imageSize.height
        let k = size.width / W
        let dest = Self.point(cc)
        let origin = Self.point("IR")
        let p = progress(now)
        let e = Self.smooth(p)
        let zMax = Self.zoomMax(cc)
        let z = dest == nil ? 1 : 1 + (zMax - 1) * CGFloat(e)

        // flight path: quadratic curve from Iran to the country, bulging "up"
        var ctrl = CGPoint.zero
        var onPath: (Double) -> CGPoint = { _ in .zero }
        var tangent: (Double) -> CGPoint = { _ in CGPoint(x: 1, y: 0) }
        var hasPath = false
        if let a = origin, let b = dest, hypot(b.x - a.x, b.y - a.y) > 4 {
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            var nx = -dy / len, ny = dx / len
            if ny > 0 { nx = -nx; ny = -ny }
            ctrl = CGPoint(x: (a.x + b.x) / 2 + nx * len * 0.28, y: (a.y + b.y) / 2 + ny * len * 0.28)
            let c = ctrl
            onPath = { s in
                let u = 1 - s
                return CGPoint(x: u * u * a.x + 2 * u * s * c.x + s * s * b.x,
                               y: u * u * a.y + 2 * u * s * c.y + s * s * b.y)
            }
            tangent = { s in
                CGPoint(x: 2 * (1 - s) * (c.x - a.x) + 2 * s * (b.x - c.x),
                        y: 2 * (1 - s) * (c.y - a.y) + 2 * s * (b.y - c.y))
            }
            hasPath = true
        }

        // camera follows the plane, then settles on the country
        var focus = CGPoint(x: W / 2, y: H / 2)
        if let d = dest {
            let lead = hasPath ? onPath(e) : d
            let settle = CGFloat(Self.smooth((p - 0.5) / 0.5))
            focus = CGPoint(x: lead.x + (d.x - lead.x) * settle, y: lead.y + (d.y - lead.y) * settle)
        }
        let halfW = W / (2 * z), halfH = H / (2 * z)
        let cx = min(max(focus.x, halfW), W - halfW)
        let cy = min(max(focus.y, halfH), H - halfH)
        func scr(_ q: CGPoint) -> CGPoint {
            CGPoint(x: size.width / 2 + (q.x - cx) * k * z, y: size.height / 2 + (q.y - cy) * k * z)
        }

        // map picture
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0B1015)))
        let img = ctx.resolve(Image("WorldMapImage"))
        let tl = scr(.zero)
        ctx.draw(img, in: CGRect(x: tl.x, y: tl.y, width: W * k * z, height: H * k * z))

        let accent = (connected || connecting) ? C.teal : C.pink
        let t = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2

        // country names
        drawLabels(&ctx, size, scr: scr, zoom: z, focus: CGPoint(x: cx, y: cy), accent: accent)

        // route
        if active, hasPath {
            var full = Path()
            let steps = 48
            for i in 0...steps {
                let q = scr(onPath(Double(i) / Double(steps)))
                if i == 0 { full.move(to: q) } else { full.addLine(to: q) }
            }
            ctx.stroke(full, with: .color(accent.opacity(0.28)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            var done = Path()
            let upto = connected && p >= 1 ? 1.0 : e
            let n = max(2, Int(48 * upto))
            for i in 0...n {
                let q = scr(onPath(upto * Double(i) / Double(n)))
                if i == 0 { done.move(to: q) } else { done.addLine(to: q) }
            }
            let phase = connected ? -CGFloat(t) * 24 : 0
            ctx.stroke(done, with: .color(accent.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [5, 4], dashPhase: phase))
        }

        // Iran (where the trip starts)
        if let o = origin {
            let q = scr(o)
            ctx.fill(circle(q, 7), with: .color(Color.white.opacity(0.22)))
            ctx.fill(circle(q, 3), with: .color(.white))
        }

        // destination marker
        if let d = dest {
            let q = scr(d)
            let a = active ? Self.smooth((p - 0.75) / 0.25) : 0.9
            if a > 0.01 {
                ctx.fill(circle(q, 26), with: .radialGradient(Gradient(colors: [accent.opacity(0.55 * a), .clear]),
                                                               center: q, startRadius: 0, endRadius: 26))
                if connected || connecting {
                    ctx.stroke(circle(q, 6 + CGFloat(t) * 22), with: .color(accent.opacity((1 - t) * 0.6 * a)), lineWidth: 1.6)
                }
                ctx.fill(circle(q, 5.5), with: .color(.white.opacity(a)))
                ctx.fill(circle(q, 3.8), with: .color(accent.opacity(a)))
            }
        }

        // plane
        if active, let d = dest, hasPath {
            let flying = p < 1
            let pos: CGPoint
            let angle: Double
            if flying {
                let s = e
                pos = scr(onPath(s))
                let tg = tangent(s)
                angle = atan2(Double(tg.y), Double(tg.x))
            } else if connecting {
                // waiting for the tunnel: circle slowly above the country
                let w = now.timeIntervalSinceReferenceDate * 1.6
                let c = scr(d)
                pos = CGPoint(x: c.x + CGFloat(cos(w)) * 20, y: c.y + CGFloat(sin(w)) * 20)
                angle = w + Double.pi / 2
            } else {
                return
            }
            ctx.fill(circle(pos, 18), with: .radialGradient(Gradient(colors: [accent.opacity(0.5), .clear]),
                                                             center: pos, startRadius: 0, endRadius: 18))
            var plane = ctx.resolve(Image(systemName: "airplane"))
            plane.shading = .color(.white)
            ctx.drawLayer { l in
                l.translateBy(x: pos.x, y: pos.y)
                l.rotate(by: .radians(angle))
                l.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1))
                l.draw(plane, in: CGRect(x: -12, y: -12, width: 24, height: 24))
            }
        }
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    /// Writes the country names on the countries: the selected one always (in a pill), the others when they fit.
    private func drawLabels(_ ctx: inout GraphicsContext, _ size: CGSize, scr: (CGPoint) -> CGPoint,
                            zoom z: CGFloat, focus: CGPoint, accent: Color) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
        var taken: [CGRect] = []
        let sel = (cc ?? "").uppercased()

        // the others: nearest to the camera first, skip any that would overlap
        let others = Array(Set(labelCodes.map { $0.uppercased() })).filter { $0 != sel && $0 != "IR" }
        let ordered = others.compactMap { code -> (String, CGPoint)? in
            guard let pt = Self.point(code) else { return nil }
            return (code, pt)
        }.sorted { hypot($0.1.x - focus.x, $0.1.y - focus.y) < hypot($1.1.x - focus.x, $1.1.y - focus.y) }

        // selected first so that it wins every collision
        if let pt = Self.point(sel) {
            let c = scr(pt)
            let text = ctx.resolve(Text(countryName(sel).uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8)
                .foregroundColor(.white))
            let m = text.measure(in: CGSize(width: 260, height: 30))
            var r = CGRect(x: c.x - m.width / 2 - 8, y: c.y + 14, width: m.width + 16, height: m.height + 7)
            if r.maxY > size.height - 3 { r.origin.y = c.y - 14 - r.height }
            r.origin.x = min(max(r.origin.x, 3), size.width - r.width - 3)
            ctx.fill(Path(roundedRect: r, cornerRadius: r.height / 2), with: .color(Color(hex: 0x0B1015).opacity(0.82)))
            ctx.stroke(Path(roundedRect: r, cornerRadius: r.height / 2), with: .color(accent), lineWidth: 1.2)
            ctx.draw(text, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
            taken.append(r.insetBy(dx: -2, dy: -2))
            taken.append(CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
        }

        for (code, pt) in ordered {
            let c = scr(pt)
            guard bounds.contains(c) else { continue }
            let printed = Self.printed.contains(code)
            let fade = printed ? 1 - Self.smooth(Double((z - 1.25) / 0.55)) : 1
            if fade < 0.05 { continue }
            let text = ctx.resolve(Text(countryName(code).uppercased()).font(.system(size: 7.5, weight: .bold)).tracking(0.6)
                .foregroundColor(Color(hex: 0x111820)))
            let m = text.measure(in: CGSize(width: 200, height: 20))
            let r = CGRect(x: c.x - m.width / 2 - 3, y: c.y - m.height / 2 - 1.5, width: m.width + 6, height: m.height + 3)
            guard bounds.contains(r), !taken.contains(where: { $0.intersects(r) }) else { continue }
            ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.white.opacity(0.9 * fade)))
            ctx.draw(text, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
            taken.append(r.insetBy(dx: -1.5, dy: -1.5))
        }
    }
}
