import UIKit
import SwiftUI

/// Regional dot map zoomed on the selected server (about a continent wide), with a pulsing marker.
/// When Tehran is inside the window an arc to the server is drawn too.
struct WorldMap: View {
    var cc: String?
    var connected: Bool

    private let spanLon = 96.0
    private let spanLat = 38.4   // 96 x 38.4 degrees = 2.5 : 1, like the card

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !connected)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
            Canvas { ctx, size in
                draw(&ctx, size, t)
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = Double(size.width), h = Double(size.height)
        let srv = Geo.latLon(cc)
        let me = Geo.latLon("IR")

        // window centred on the server (or on Iran when nothing is selected), kept inside the world
        let cLat = srv?.lat ?? me?.lat ?? 40.0
        let cLon = srv?.lon ?? me?.lon ?? 30.0
        let lon0 = min(max(cLon - spanLon / 2, -180.0), 180.0 - spanLon)
        let latTop = min(max(cLat + spanLat / 2, -60.0 + spanLat), 84.0)

        func px(_ lon: Double) -> CGFloat { CGFloat((lon - lon0) / spanLon * w) }
        func py(_ lat: Double) -> CGFloat { CGFloat((latTop - lat) / spanLat * h) }

        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(hex: 0x1E2B3A), Color(hex: 0x172230)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        // land dots (only the visible window is drawn)
        let cell = CGFloat(w / spanLon)
        let r = cell * 0.36
        let land = Color(hex: 0x63758C)
        let colFrom = min(max(Int(lon0 + 180.0), 0), Geo.cols - 1)
        let colTo = min(max(Int(lon0 + spanLon + 180.0), 0), Geo.cols - 1)
        let rowFrom = min(max(Int(84.0 - latTop), 0), Geo.rows - 1)
        let rowTo = min(max(Int(84.0 - (latTop - spanLat)), 0), Geo.rows - 1)
        var dots = Path()
        for row in rowFrom...rowTo {
            let line = Geo.land[row]
            let y = py(84.0 - (Double(row) + 0.5))
            for col in colFrom...colTo where line[col] {
                let x = px(-180.0 + Double(col) + 0.5)
                dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        }
        ctx.fill(dots, with: .color(land))

        let accent = connected ? C.teal : C.pink
        func circle(_ c: CGPoint, _ rad: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad))
        }

        guard let s = srv else { return }
        let sp = CGPoint(x: px(s.lon), y: py(s.lat))
        if let m = me {
            let mp = CGPoint(x: px(m.lon), y: py(m.lat))
            if mp.x >= 0 && mp.x <= size.width && mp.y >= 0 && mp.y <= size.height {
                let dist = hypot(sp.x - mp.x, sp.y - mp.y)
                var path = Path()
                path.move(to: mp)
                path.addQuadCurve(to: sp, control: CGPoint(x: (mp.x + sp.x) / 2, y: min(mp.y, sp.y) - dist * 0.35))
                ctx.stroke(path, with: .color(accent.opacity(0.2)), style: StrokeStyle(lineWidth: cell * 1.6, lineCap: .round))
                let phase = connected ? -CGFloat(t) * cell * 6 : 0
                ctx.stroke(path, with: .color(accent.opacity(connected ? 0.95 : 0.55)),
                           style: StrokeStyle(lineWidth: cell * 0.5, lineCap: .round, dash: [cell * 1.8, cell * 1.8], dashPhase: phase))
                ctx.fill(circle(mp, cell * 2.4), with: .color(.white.opacity(0.25)))
                ctx.fill(circle(mp, cell * 0.9), with: .color(.white))
            }
        }
        ctx.fill(circle(sp, cell * 7), with: .radialGradient(Gradient(colors: [accent.opacity(0.55), .clear]),
                                                              center: sp, startRadius: 0, endRadius: cell * 7))
        ctx.stroke(circle(sp, cell * (1.5 + CGFloat(t) * 6)), with: .color(accent.opacity((1 - t) * 0.6)), lineWidth: cell * 0.45)
        ctx.fill(circle(sp, cell * 1.2), with: .color(.white))
        ctx.fill(circle(sp, cell * 0.85), with: .color(accent))
    }
}
