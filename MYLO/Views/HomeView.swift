#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var vm: VpnViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var onChange: () -> Void
    var onAssistant: () -> Void
    var onAppearance: () -> Void

    @State private var checks: [Check] = []
    private var checksTotal: Int { max(checks.count, 4) }

    var body: some View {
        let info = vm.connectedInfo
        let connected = info != nil
        let connecting = vm.isConnecting
        let server = vm.servers.first { $0.address == vm.selected }
        let best = vm.servers.filter { $0.pingMs != nil }.min { $0.pingMs! < $1.pingMs! }
        let ovpn = activeOpenVPN()
        let shown: Server? = ovpn.map { Server(name: $0.name, address: "", cc: configCc($0.name, host: $0.host)) }
            ?? (vm.auto ? (best ?? server) : server)

        let isRegular = horizontalSizeClass == .regular
        let heroHeight: CGFloat = isRegular ? 250 : 312

        VStack(spacing: 0) {
            hero(connected: connected, connecting: connecting)
                .frame(height: heroHeight)

            if isRegular {
                // Regular size class (iPad landscape): sidebar + map
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        // Sidebar: controls
                        VStack(spacing: 12) {
                            locationCard(shown: shown, server: server, best: best, ovpn: ovpn)
                            timeAndProtocol
                            assistantCard
                            liveCard(connected: connected)
                            if connected { statsCard }
                        }
                        .padding(.horizontal, 20)
                        .frame(width: min(geo.size.width * 0.4, 400))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding()

                        // Map
                        WorldMap(cc: shown?.cc, connected: connected, connecting: connecting,
                                 labelCodes: vm.servers.map { $0.cc }.filter { !$0.isEmpty })
                            .aspectRatio(WorldMap.imageSize.width / WorldMap.imageSize.height, contentMode: .fit)
                            .background(C.mapBg)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .padding()
                    }
                }
            } else {
                // Compact size class (iPhone, iPad portrait): original vertical scroll
                ScrollView {
                    VStack(spacing: 0) {
                        if connecting && !vm.detail.isEmpty {
                            Text(vm.detail).font(.mylo(12)).foregroundColor(C.muted)
                                .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 2)
                        }
                        if let m = vm.failedMessage {
                            Text(m).font(.mylo(12)).foregroundColor(C.danger)
                                .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.vertical, 4)
                        }
                        if vm.mode == .profile && !connected && !connecting {
                            Text(vm.notice.isEmpty
                                 ? "Tap the power button. The first time it installs the VPN profile and guides you through a one-time Shortcuts setup; after that the button turns the VPN on and off."
                                 : vm.notice)
                                .font(.mylo(12)).foregroundColor(C.muted)
                                .multilineTextAlignment(.center).padding(.horizontal, 28).padding(.top, 4)
                        }
                        Spacer().frame(height: 6)

                        VStack(spacing: 12) {
                            locationCard(shown: shown, server: server, best: best, ovpn: ovpn)
                            WorldMap(cc: shown?.cc, connected: connected, connecting: connecting,
                                     labelCodes: vm.servers.map { $0.cc }.filter { !$0.isEmpty })
                                .aspectRatio(WorldMap.imageSize.width / WorldMap.imageSize.height, contentMode: .fit)
                                .background(C.mapBg)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            timeAndProtocol
                            assistantCard
                            liveCard(connected: connected)
                            if connected { statsCard }
                            Spacer().frame(height: 12)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .task { checks = await Task.detached(priority: .utility) { deviceChecks() }.value }
        // Start the network loops a moment after the first frame so the app appears instantly.
        .task { try? await Task.sleep(nanoseconds: 800_000_000); await vm.liveLoop() }
        .task { try? await Task.sleep(nanoseconds: 2_500_000_000); await vm.livePingLoop(60) }   // keeps pings fresh for "Fastest Location"
    }

    // MARK: - Helper functions

    /// The OpenVPN profile chosen in Locations > OpenVPN (only the OpenVPN build can connect with it).
    private func activeOpenVPN() -> ImportedConfig? {
        #if OPENVPN
        let id = Store.shared.activeOvpn
        return id.isEmpty ? nil : ConfigStore.list().first { $0.id == id && $0.kind == .openvpn }
        #else
        return nil
        #endif
    }

    private func locationCard(shown: Server?, server: Server?, best: Server?, ovpn: ImportedConfig?) -> some View {
        Button(action: onChange) {
            HStack(spacing: 10) {
                Text(flagEmoji(shown?.cc ?? "")).font(.mylo(22))
                VStack(alignment: .leading, spacing: 0) {
                    Text(ovpn != nil ? "OpenVPN" : (vm.auto ? (best?.name ?? "Measuring...") : "Selected Location"))
                        .font(.mylo(12)).foregroundColor(C.muted).lineLimit(1)
                    Text(ovpn?.name ?? (vm.auto ? "Fastest Location" : (server?.name ?? "No server selected")))
                        .font(.mylo(19, weight: .semibold)).foregroundColor(C.ink).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(C.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var timeAndProtocol: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            let week = vm.store.week()
            let total = week.reduce(0, +)
            let maxV = max(week.max() ?? 0, 1800)
            let today = Store.todayIndex()
            let letters = Array("MTWTFSS")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Time Protected").font(.mylo(14)).foregroundColor(C.muted)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(total >= 3600 ? "\(total / 3600)h" : "\(total / 60)m")
                                .font(.mylo(20, weight: .bold)).foregroundColor(C.ink)
                            Text("this week").font(.mylo(11)).foregroundColor(C.muted)
                        }
                        Spacer(minLength: 4)
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(0..<7, id: \.self) { i in
                                VStack(spacing: 1) {
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 4).fill(i > today ? C.track.opacity(0.25) : C.track)
                                        RoundedRectangle(cornerRadius: 4).fill(i == today ? C.teal : C.teal.opacity(0.55))
                                            .frame(height: 30 * min(max(CGFloat(week[i]) / CGFloat(maxV), 0.06), 1))
                                    }
                                    .frame(width: 8, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(String(letters[i])).font(.mylo(8)).foregroundColor(C.muted)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 85, alignment: .topLeading)
                .background(C.card).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Protocol").font(.mylo(14)).foregroundColor(C.muted)
                        Spacer()
                        Image(systemName: "chevron.right").font(.mylo(12)).foregroundColor(C.ink)
                    }
                    Spacer(minLength: 0)
                    Text("Selected:").font(.mylo(12)).foregroundColor(C.ink)
                    Text(activeOpenVPN() != nil ? "OpenVPN" : "IKEv2").font(.mylo(20, weight: .bold)).foregroundColor(C.ink)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 85, alignment: .topLeading)
                .background(C.card).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var assistantCard: some View {
        let done = checks.filter { $0.ok }.count
        let frac = Double(done) / Double(checksTotal)
        return Button(action: onAssistant) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Secure Device Assistant").font(.mylo(14)).foregroundColor(C.muted)
                    Spacer()
                    Image(systemName: "chevron.right").font(.mylo(12)).foregroundColor(C.ink)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(done) out of \(checksTotal)").font(.mylo(18, weight: .bold)).foregroundColor(C.ink)
                        Text("marked as done").font(.mylo(15)).foregroundColor(C.ink)
                    }
                    Spacer()
                    ZStack(alignment: .bottom) {
                        Canvas { ctx, size in
                            let sw: CGFloat = 14
                            let rad = size.width / 2 - sw / 2
                            let c = CGPoint(x: size.width / 2, y: size.height)
                            ctx.stroke(arcPath(center: c, radius: rad, from: 180, to: 360), with: .color(C.track.opacity(0.2)), lineWidth: sw)
                            if frac > 0 {
                                ctx.stroke(arcPath(center: c, radius: rad, from: 180, to: 180 + 180 * frac), with: .color(C.teal.opacity(0.85)), lineWidth: sw)
                            }
                        }
                        Text("\(done) / \(checksTotal)").font(.mylo(16)).foregroundColor(C.muted).padding(.bottom, 2)
                    }
                    .frame(width: 104, height: 54)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 103, alignment: .topLeading)
            .background(C.card).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func liveCard(connected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live ping - direct").font(.mylo(12)).foregroundColor(C.muted)
                if let ms = vm.live.directMs {
                    Text("\(ms) ms").font(.mylo(18, weight: .bold)).foregroundColor(C.teal)
                } else {
                    Text(connected ? "paused" : "no response").font(.mylo(18, weight: .bold))
                        .foregroundColor(connected ? C.muted : C.danger)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Via VPN").font(.mylo(12)).foregroundColor(C.muted)
                Text(connected ? (vm.live.vpnMs.map { "\($0) ms" } ?? "...") : "-")
                    .font(.mylo(18, weight: .bold)).foregroundColor(C.ink)
            }
        }
        .card(14)
    }

    private var statsCard: some View {
        let ss = vm.stats
        return VStack(spacing: 10) {
            HStack {
                metric("Download", fmtBits(ss.downBps), C.teal); Spacer()
                metric("Upload", fmtBits(ss.upBps), C.pink); Spacer()
                metric("Latency", ss.latencyMs.map { "\($0) ms" } ?? "-", C.ink)
            }
            HStack {
                metric("Public IP", vm.showIp ? (ss.publicIp ?? "...") : "Hidden", C.ink); Spacer()
                metric("RX", fmtBytes(ss.rx), C.ink); Spacer()
                metric("TX", fmtBytes(ss.tx), C.ink)
            }
        }
        .card(14)
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.mylo(12)).foregroundColor(C.muted)
            Text(value).font(.mylo(16, weight: .semibold)).foregroundColor(color)
        }
    }

    // MARK: hero

    private func hero(connected: Bool, connecting: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height - 64)
                let r = size.width * 0.62
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [C.glow, .clear]), center: c, startRadius: 0, endRadius: r))
                for f in [0.575, 0.40] {
                    let rr = size.width * CGFloat(f)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                               with: .color(C.glow.opacity(0.6)), lineWidth: 1.5)
                }
            }
            .opacity(connected ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.7), value: connected)

            // extra core glow that only appears while protected
            Circle()
                .fill(RadialGradient(colors: [C.teal.opacity(0.42), C.teal.opacity(0.12), .clear],
                                     center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 340)
                .offset(y: 106)
                .opacity(connected ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: connected)
                .allowsHitTesting(false)

            HStack {
                Image("Logo").resizable().scaledToFit().frame(height: 26)
                    .padding(.top, 62).padding(.leading, 20)
                    .frame(maxHeight: .infinity, alignment: .top)
                Spacer()
                VStack {
                    Button(action: onAppearance) {
                        Image(systemName: "paintpalette.fill").font(.mylo(26)).foregroundColor(C.ink)
                    }
                    .padding(.top, 58).padding(.trailing, 16)
                    Spacer()
                }
            }
            ZStack {
                // halo rings: faint when off, bright when on
                Circle().stroke((connected ? C.teal : C.glow).opacity(connected ? 0.35 : 0.30), lineWidth: 1.5)
                    .frame(width: 134, height: 134)
                Circle().stroke((connected ? C.teal : C.glow).opacity(connected ? 0.16 : 0.15), lineWidth: 1.5)
                    .frame(width: 162, height: 162)
                if connected {
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                        Circle().stroke(C.teal.opacity(0.30 * (1 - t)), lineWidth: 2)
                            .frame(width: 112 + 70 * t, height: 112 + 70 * t)
                    }
                }
                if connecting {
                    TimelineView(.animation) { tl in
                        let deg = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360
                        Circle().trim(from: 0, to: 0.3)
                            .stroke(C.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(deg))
                    }
                }
                Button(action: { vm.toggle() }) {
                    ZStack {
                        Circle().fill(connected
                                          ? AnyShapeStyle(LinearGradient(colors: [C.teal, C.teal.opacity(0.68)], startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(LinearGradient(colors: [C.card, C.card.opacity(0.82)], startPoint: .top, endPoint: .bottom)))
                        // glossy glass rim + top highlight
                        Circle().stroke(LinearGradient(colors: [Color.white.opacity(connected ? 0.6 : 0.4), Color.white.opacity(0.04)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.6)
                        Circle().fill(LinearGradient(colors: [Color.white.opacity(connected ? 0.22 : 0.10), .clear],
                                                     startPoint: .top, endPoint: .center))
                            .padding(4)
                        Image(systemName: "power").font(.mylo(42, weight: .semibold))
                            .foregroundColor(connected ? .white : (connecting ? C.muted : C.pink))
                    }
                    .frame(width: 108, height: 108)
                    .shadow(color: connected ? C.teal.opacity(0.6) : Color.black.opacity(0.18),
                            radius: connected ? 28 : 14, y: connected ? 0 : 6)
                }
                .buttonStyle(.plain)
            }
            .animation(.easeInOut(duration: 0.5), value: connected)
            .padding(.bottom, 10)
        }
        .frame(height: 312)
    }
}