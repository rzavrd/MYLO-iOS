import UIKit
import SwiftUI

struct AppRoot: View {
    @EnvironmentObject var vm: VpnViewModel
    @EnvironmentObject var auth: AuthModel
    @ObservedObject private var pal = Pal.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var tab = 0
    @State private var sub: String? = nil

    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()
            if !Defaults.requireLogin || auth.isLoggedIn { main } else { LoginView() }
        }
        .id(pal.cur.name + (pal.cur.dark ? "-d" : "-l") + "\(textSize)")   // re-create the tree when palette or text size changes
        .preferredColorScheme(forcedScheme)
        .overlay(alignment: .bottom) {
            if let t = vm.toast {
                Text(t).font(.mylo(14)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .padding(.bottom, 100).padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: vm.toast)
        .onAppear { applyTheme(); if Defaults.requireLogin { Task { await auth.refresh() } } }
        .onValueChange(of: scheme) { _ in applyTheme() }
        .onValueChange(of: vm.theme) { _ in applyTheme() }
        .onValueChange(of: phase) { p in
            if p == .active { vm.vpn.startWatching(); if Defaults.requireLogin { Task { await auth.refresh() } } }
        }
        .onValueChange(of: auth.isLoggedIn) { _ in tab = 0; sub = nil }
    }

    private var forcedScheme: ColorScheme? {
        if vm.theme == "System" { return nil }
        return pal.cur.dark ? ColorScheme.dark : ColorScheme.light
    }

    private func applyTheme() {
        let p = Palettes.byName(vm.theme, systemDark: scheme == .dark)
        if p.name != pal.cur.name { pal.cur = p }
    }

    private var main: some View {
        page.safeAreaInset(edge: .bottom, spacing: 0) {
            if sub == nil { NavBar(tab: $tab) }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch sub ?? "" {
        case "locations": LocationsView { sub = nil }
        case "appearance": AppearanceView { sub = nil }
        case "assistant": AssistantView { sub = nil }
        case "advanced": AdvancedView(onBack: { sub = nil }, onImport: { sub = "configs" })
        case "configs": ConfigsView { sub = nil }
        case "log":
            VStack(spacing: 0) {
                SubHeader("Connection Log", onBack: { sub = nil })
                LogView()
            }
        default:
            switch tab {
            case 0: HomeView(onChange: { sub = "locations" }, onAssistant: { sub = "assistant" }, onAppearance: { sub = "appearance" })
            case 1: StatsView()
            case 2: SpeedTestView(s: vm.speed)
            case 3: HelpView(go: { sub = $0 })
            default: ProfileView(go: { sub = $0 })
            }
        }
    }
}

/// Floating glass pill bar (Liquid Glass on iOS 26+, frosted material on older iOS).
struct NavBar: View {
    @Binding var tab: Int
    private let items: [(String, String)] = [
        ("VPN", "power"), ("Stats", "chart.bar.fill"), ("Speed Test", "speedometer"),
        ("Help", "questionmark.circle.fill"), ("Profile", "person.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { i in
                Button { tab = i } label: {
                    VStack(spacing: 2) {
                        Image(systemName: items[i].1).font(.mylo(20))
                        Text(items[i].0).font(.mylo(11, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundColor(C.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        Capsule().fill(i == tab ? C.barSel.opacity(0.55) : Color.clear)
                            .overlay(Capsule().stroke(Color.white.opacity(i == tab ? 0.35 : 0), lineWidth: 0.8))
                    )
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 66)   // fixed height: children use maxHeight: .infinity, so without a cap the bar fills the whole screen
        .modifier(GlassBar())
        .padding(.horizontal, 18).padding(.vertical, 8)
    }
}

/// Liquid Glass capsule on iOS 26+; translucent blur with a light rim on earlier versions.
private struct GlassBar: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(fallback)
        }
        #else
        content.background(fallback)
        #endif
    }

    private var fallback: some View {
        Capsule().fill(.ultraThinMaterial)
            .overlay(Capsule().fill(C.barBg.opacity(0.18)))
            .overlay(Capsule().stroke(
                LinearGradient(colors: [Color.white.opacity(0.65), Color.white.opacity(0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
    }
}
