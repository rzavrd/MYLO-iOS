import UIKit
import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject var vm: VpnViewModel
    @ObservedObject var s: SpeedTest

    private static func gaugeFrac(_ m: Double) -> Double {
        let pts: [(Double, Double)] = [(0, 0), (100, 0.25), (250, 0.5), (500, 0.75), (1000, 1)]
        if m >= 1000 { return 1 }
        for i in 1..<pts.count where m <= pts[i].0 {
            let a = pts[i - 1], b = pts[i]
            return a.1 + (m - a.0) / (b.0 - a.0) * (b.1 - a.1)
        }
        return 1
    }

    private func f1(_ d: Double?) -> String { d.map { String(format: "%.1f", $0) } ?? "-" }

    var body: some View {
        let connected = vm.isConnected
        let server = vm.servers.first { $0.address == vm.selected }
        let shown = s.running ? s.liveMbps : (s.down ?? 0)
        let frac = Self.gaugeFrac(shown)

        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Canvas { ctx, size in
                        let cx = size.width / 2
                        let cy = size.height - 64
                        let r = size.width * 0.36
                        let c = CGPoint(x: cx, y: cy)
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - size.width * 0.8, y: cy - size.width * 0.8, width: size.width * 1.6, height: size.width * 1.6)),
                                 with: .radialGradient(Gradient(colors: [C.glow, .clear]), center: c, startRadius: 0, endRadius: size.width * 0.8))
                        ctx.stroke(arcPath(center: c, radius: r, from: 180, to: 360), with: .color(C.track.opacity(0.25)),
                                   style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        if frac > 0.001 {
                            ctx.stroke(arcPath(center: c, radius: r, from: 180, to: 180 + 180 * frac), with: .color(C.teal),
                                       style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        }
                        let marks: [(Int, Double)] = [(0, 0), (100, 0.25), (250, 0.5), (500, 0.75), (1000, 1)]
                        for (v, f) in marks {
                            let a = (180 + 180 * f) * .pi / 180
                            let rr = r * 0.78
                            let p = CGPoint(x: cx + rr * CGFloat(cos(a)), y: cy + rr * CGFloat(sin(a)))
                            ctx.draw(Text("\(v)").font(.mylo(14)).foregroundColor(C.muted), at: p)
                        }
                    }
                    Button { if s.running { s.stop() } else { s.start() } } label: {
                        Image(systemName: s.running ? "stop.fill" : "play.fill").font(.mylo(44)).foregroundColor(C.ink)
                            .frame(width: 120, height: 120).background(Circle().fill(C.card))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }
                .frame(height: 300)

                Text(s.running ? "\(s.phase)  \(String(format: "%.1f", shown)) Mbps"
                     : (s.phase == "Done" ? "Test complete" : "Tap to start the Speed Test"))
                    .font(.mylo(18, weight: .bold))
                    .foregroundColor(Pal.shared.cur.dark ? Color(hex: 0x14202B) : Color.white)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Pal.shared.cur.dark ? Color.white : Color(hex: 0x14202B)))

                if let e = s.error { Text(e).font(.mylo(13)).foregroundColor(C.danger).padding(20) }

                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        infoLine("VPN Server:", server?.name ?? "-", accent: true)
                        infoLine("VPN IP:", connected && vm.showIp ? (vm.stats.publicIp ?? "-") : "Hidden")
                        infoLine("Protocol:", connected ? "IKEv2" : "-")
                        infoLine("Test Endpoint:", "speed.cloudflare.com")
                        infoLine("Test Endpoint IP:", s.endpointIp ?? "-")
                        Rectangle().fill(C.muted.opacity(0.3)).frame(height: 1)
                        bigLine("Download", "\(f1(s.down)) Mbps")
                        bigLine("Upload", "\(f1(s.up)) Mbps")
                        bigLine("Latency", "\(s.latency.map { String($0) } ?? "-") ms")
                        bigLine("Jitter", "\(s.jitter.map { String($0) } ?? "-") ms")
                        bigLine("Packet loss", "\(s.loss.map { String($0) } ?? "-") %")
                    }
                    .card(20)

                    VStack(spacing: 8) {
                        infoLine("Your Country:", (s.country ?? "").isEmpty ? "-" : countryName(s.country ?? ""))
                        infoLine("Your Provider:", (s.provider ?? "").isEmpty ? "-" : (s.provider ?? ""))
                        infoLine("Your IP:", (s.ip ?? "").isEmpty ? "-" : (s.ip ?? ""))
                    }
                    .card(20)

                    Text("The test runs through the VPN while connected, so it shows the tunnel's speed.")
                        .font(.mylo(12)).foregroundColor(C.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
        }
    }

    private func infoLine(_ k: String, _ v: String, accent: Bool = false) -> some View {
        HStack {
            Text(k).font(.mylo(17)).foregroundColor(C.ink)
            Spacer()
            Text(v).font(.mylo(17, weight: accent ? .bold : .regular)).foregroundColor(accent ? C.teal : C.ink).lineLimit(1)
        }
    }

    private func bigLine(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.mylo(18)).foregroundColor(C.muted)
            Spacer()
            Text(v).font(.mylo(20, weight: .bold)).foregroundColor(C.ink)
        }
        .padding(.vertical, 6)
    }
}
