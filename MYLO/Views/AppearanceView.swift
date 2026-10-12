import UIKit
import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject var vm: VpnViewModel
    @Environment(\.colorScheme) private var scheme
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SubHeader("Appearance", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Color Scheme").font(.mylo(22, weight: .bold)).foregroundColor(C.ink).padding(.vertical, 14)
                    let rows = stride(from: 0, to: Palettes.names.count, by: 3).map { Array(Palettes.names[$0..<min($0 + 3, Palettes.names.count)]) }
                    ForEach(0..<rows.count, id: \.self) { r in
                        HStack(alignment: .top) {
                            ForEach(rows[r], id: \.self) { n in thumb(n) }
                            if rows[r].count < 3 { Spacer() }
                        }
                        .padding(.bottom, 16)
                    }
                    Text("The home-screen icon can't be switched on iOS without extra icon files; the colors above apply instantly.")
                        .font(.mylo(12)).foregroundColor(C.muted).padding(.top, 6)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func thumb(_ name: String) -> some View {
        let selected = name == vm.theme
        return Button { vm.setTheme(name) } label: {
            VStack(spacing: 6) {
                Canvas { ctx, size in
                    if name == "System" {
                        var l = ctx; l.clip(to: Path(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)))
                        drawThumb(&l, size, Palettes.sand)
                        var r = ctx; r.clip(to: Path(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)))
                        drawThumb(&r, size, Palettes.twilight)
                    } else {
                        drawThumb(&ctx, size, Palettes.byName(name, systemDark: scheme == .dark))
                    }
                }
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? C.teal : C.muted.opacity(0.4), lineWidth: selected ? 3 : 1))
                Text(name).font(.mylo(15)).foregroundColor(selected ? C.teal : C.ink)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func drawThumb(_ ctx: inout GraphicsContext, _ size: CGSize, _ p: Palette) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(p.bg))
        let hero = size.height * 0.4
        let c = CGPoint(x: size.width / 2, y: hero)
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: hero)),
                 with: .radialGradient(Gradient(colors: [p.glow, p.glow.opacity(0.35)]), center: c, startRadius: 0, endRadius: size.width * 0.8))
        let br = size.width * 0.15
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: 2 * br, height: 2 * br)), with: .color(p.dark ? p.card : Color.white))
        let card = p.dark ? p.card : p.bar
        let x0 = size.width * 0.1, cw = size.width * 0.8, ch = size.height * 0.085
        ctx.fill(Path(roundedRect: CGRect(x: x0, y: hero + size.height * 0.1, width: cw, height: ch), cornerRadius: 6), with: .color(card))
        let half = (cw - size.width * 0.04) / 2
        for row in 0..<2 {
            let y = hero + size.height * (0.22 + 0.1 * CGFloat(row))
            ctx.fill(Path(roundedRect: CGRect(x: x0, y: y, width: half, height: ch), cornerRadius: 6), with: .color(card))
            ctx.fill(Path(roundedRect: CGRect(x: x0 + half + size.width * 0.04, y: y, width: half, height: ch), cornerRadius: 6), with: .color(card))
        }
    }
}
