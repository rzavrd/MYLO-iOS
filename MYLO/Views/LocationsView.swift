#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI

struct LocationsView: View {
    @EnvironmentObject var vm: VpnViewModel
    var onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        _protoTab = State(initialValue: Store.shared.activeOvpn.isEmpty ? 0 : 1)
    }

    @State private var protoTab = 0          // 0 = IKEv2, 1 = OpenVPN, 2 = VLESS (and VMess / Trojan)
    @State private var cfgTick = 0
    @State private var cfgNote: String?
    @State private var q = ""
    @State private var tab = 0
    @State private var region = "All Regions"
    @State private var sortBy = "Locations"
    @State private var expanded = Set<String>()
    @State private var showAdd = false
    @State private var showImport = false
    @State private var showHelp = false

    var body: some View {
        let query = q.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = vm.servers.filter {
            query.isEmpty || $0.name.lowercased().contains(query)
                || countryName($0.cc).lowercased().contains(query)
        }
        let ranked = vm.servers.filter { $0.pingMs != nil }.sorted { $0.pingMs! < $1.pingMs! }
        let best = ranked.first
        let recents = recentServers()
        let favServers = vm.servers.filter { vm.favs.contains($0.address) }

        VStack(spacing: 0) {
            SubHeader("VPN Locations", onBack: onBack) {
                Button { showHelp = true } label: {
                    Text("?").font(.mylo(20, weight: .bold)).foregroundColor(C.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(C.barBg))
                }
            }

            #if !APPSTORE
            let cfgs = ConfigStore.list()
            Segmented(options: ["IKEv2", "OpenVPN \(cfgs.filter { $0.kind == .openvpn }.count)",
                                "VLESS \(cfgs.filter { $0.kind != .openvpn }.count)"], selected: $protoTab)
            Spacer().frame(height: 10)
            #endif
            if protoTab == 0 {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(C.muted)
                TextField("Search for a city or country", text: $q)
#if canImport(UIKit)
                    .autocapitalization(.none)
#endif
                    .autocorrectionDisabled().foregroundColor(C.ink)
            }
            .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(C.barBg)).padding(.horizontal, 20)
            Spacer().frame(height: 12)
            Segmented(options: ["Recommended", "All Locations"], selected: $tab)
            Spacer().frame(height: 4)

            if tab == 1 && query.isEmpty {
                HStack {
                    Menu {
                        ForEach(Regions.names, id: \.self) { r in Button(r) { region = r } }
                    } label: { Label(region, systemImage: "chevron.down").foregroundColor(C.teal) }
                    Spacer()
                    Menu {
                        ForEach(["Locations", "Name", "Ping"], id: \.self) { r in Button(r) { sortBy = r } }
                    } label: { Label("Sort: \(sortBy)", systemImage: "chevron.down").foregroundColor(C.teal) }
                }
                .padding(.horizontal, 20).padding(.vertical, 4)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !query.isEmpty {
                        ForEach(filtered.sorted { ($0.pingMs ?? Int.max) < ($1.pingMs ?? Int.max) }) { s in
                            row(s, compact: false, detail: true, fav: true, delete: false)
                        }
                    } else if tab == 0 {
                        header("bolt.fill", "Fastest Servers", "Top 5 (Ping)", chevron: true)
                        if let best {
                            fastestRow(best)
                            ForEach(Array(ranked.prefix(5).dropFirst())) { s in row(s, compact: false, detail: false, fav: false, delete: false) }
                        } else {
                            Text(vm.pinging ? "Measuring servers..." : "No ping answers yet. Pull down in a moment or check your connection.")
                                .foregroundColor(C.muted).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !recents.isEmpty {
                            header("clock.arrow.circlepath", "Recent Locations", "Last \(recents.count)", chevron: true)
                            ForEach(recents) { s in row(s, compact: true, detail: false, fav: false, delete: false) }
                        }
                        if !favServers.isEmpty {
                            header("heart.fill", "Favorites", "\(favServers.count)", chevron: false)
                            ForEach(favServers) { s in row(s, compact: false, detail: false, fav: true, delete: false) }
                        }
                        header("globe", "All Countries", "", chevron: false)
                        Text("\(vm.servers.count) locations  |  \(Set(vm.servers.map { $0.cc }).count) countries")
                            .font(.mylo(13)).foregroundColor(C.muted)
                            .padding(.leading, 46).padding(.bottom, 4).frame(maxWidth: .infinity, alignment: .leading)
                        countryGroups(vm.servers, order: nil, deletable: false)
                    } else {
                        let groups = Dictionary(grouping: vm.servers) { $0.cc.isEmpty ? "??" : $0.cc }
                            .filter { region == "All Regions" || Regions.of($0.key) == region }
                        let order: [String] = {
                            switch sortBy {
                            case "Name": return groups.keys.sorted { countryName($0) < countryName($1) }
                            case "Ping": return groups.keys.sorted { bestPing(groups[$0]!) < bestPing(groups[$1]!) }
                            default: return groups.keys.sorted { groups[$0]!.count > groups[$1]!.count }
                            }
                        }()
                        countryGroups(vm.servers.filter { groups.keys.contains($0.cc.isEmpty ? "??" : $0.cc) }, order: order, deletable: true)
                    }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
            } else {
                configPane
            }
        }
        .task { vm.refreshHistory() }
        .task { await vm.livePingLoop(4) }   // live ping while this screen is open
        .alert("VPN Locations", isPresented: $showHelp) {
            Button("Add server") { showAdd = true }
            Button("Import list") { showImport = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pings are measured live over your real connection and refresh every few seconds. Great is under 100 ms, Good under 180, Fair under 300. The best servers are listed first.")
        }
        .sheet(isPresented: $showAdd) { AddServerSheet().environmentObject(vm) }
        .sheet(isPresented: $showImport) { ImportSheet().environmentObject(vm) }
    }

    // MARK: helpers

    private func bestPing(_ g: [Server]) -> Int { g.compactMap { $0.pingMs }.min() ?? Int.max }

    private func recentServers() -> [Server] {
        var out: [Server] = []
        for h in vm.history {
            if let s = vm.servers.first(where: { $0.name == h.server }), !out.contains(where: { $0.address == s.address }) { out.append(s) }
            if out.count == 3 { break }
        }
        return out
    }

    private func pick(_ s: Server) { vm.select(s.address); onBack() }

    // MARK: imported configs (OpenVPN / VLESS), kept apart from the IKEv2 locations

    private var canConnectOpenVPN: Bool {
        #if OPENVPN
        return true
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var configPane: some View {
        let kinds: [ConfigKind] = protoTab == 1 ? [.openvpn] : [.vless, .vmess, .trojan]
        let items = ConfigStore.list().filter { kinds.contains($0.kind) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let _ = cfgTick
        ScrollView {
            LazyVStack(spacing: 0) {
                Text(protoTab == 1
                     ? (canConnectOpenVPN ? "Your imported OpenVPN profiles. Tap one to use it, then press the power button."
                                          : "Your imported OpenVPN profiles. They connect only in the MYLO-OpenVPN build (see docs/OPENVPN.md).")
                     : "Your imported VLESS / VMess / Trojan links. They are saved only: this build has no core to connect with them yet.")
                    .font(.mylo(12)).foregroundColor(C.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                if let m = cfgNote {
                    Text(m).font(.mylo(13)).foregroundColor(C.ink).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
                }
                if items.isEmpty {
                    Text(protoTab == 1 ? "No OpenVPN profiles yet. Open a .ovpn file with MYLO, or add it under Profile > Add configuration."
                                       : "No VLESS links yet. Add them under Profile > Add configuration.")
                        .foregroundColor(C.muted).padding(.vertical, 30).frame(maxWidth: .infinity)
                }
                ForEach(items) { c in configRow(c) }
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
    }

    private func configRow(_ c: ImportedConfig) -> some View {
        let isOvpn = c.kind == .openvpn
        let active = isOvpn && Store.shared.activeOvpn == c.id
        let usable = isOvpn && canConnectOpenVPN
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if usable { Store.shared.activeOvpn = c.id; onBack() }
                    else { cfgNote = isOvpn ? "OpenVPN connects only in the MYLO-OpenVPN build." : "\(c.kind.title) can't connect yet: it needs a tunnel core that isn't included." }
                } label: {
                    HStack(spacing: 14) {
                        Text(flagEmoji(configCc(c.name, host: c.host))).font(.mylo(26))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).font(.mylo(18, weight: active ? .bold : .regular))
                                .foregroundColor(active ? C.teal : (usable ? C.ink : C.muted)).lineLimit(1)
                            Text(c.kind.title).font(.mylo(12)).foregroundColor(C.muted)
                        }
                        Spacer()
                        if active { Image(systemName: "checkmark.circle.fill").foregroundColor(C.teal) }
                    }
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { ConfigStore.remove(c.id); cfgTick += 1 } label: {
                    Image(systemName: "trash").foregroundColor(C.muted).frame(width: 36, height: 36)
                }
            }
            divider
        }
    }

    @ViewBuilder
    private func countryGroups(_ list: [Server], order: [String]?, deletable: Bool) -> some View {
        let groups = Dictionary(grouping: list) { $0.cc.isEmpty ? "??" : $0.cc }
        let keys = order ?? groups.keys.sorted { countryName($0) < countryName($1) }
        ForEach(keys, id: \.self) { cc in
            if let g = groups[cc] {
                Button {
                    if expanded.contains(cc) { expanded.remove(cc) } else { expanded.insert(cc) }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            Text(flagEmoji(cc == "??" ? "" : cc)).font(.mylo(26))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cc == "??" ? "Other" : countryName(cc)).font(.mylo(18)).foregroundColor(C.ink)
                                let bm = bestPing(g)
                                Text("\(g.count) location\(g.count == 1 ? "" : "s")" + (bm == Int.max ? "" : "  |  best \(bm) ms"))
                                    .font(.mylo(13)).foregroundColor(C.muted)
                            }
                            Spacer()
                            Image(systemName: expanded.contains(cc) ? "chevron.up" : "chevron.down").foregroundColor(C.ink)
                        }
                        .frame(minHeight: 56)
                        divider
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded.contains(cc) {
                    ForEach(g.sorted { ($0.pingMs ?? Int.max) < ($1.pingMs ?? Int.max) }) { s in
                        row(s, compact: false, detail: true, fav: true, delete: deletable)
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(C.muted.opacity(0.2)).frame(height: 1).padding(.leading, 46)
    }

    private func header(_ icon: String, _ title: String, _ right: String, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.mylo(22)).foregroundColor(C.muted).frame(width: 28)
            Text(title).font(.mylo(22, weight: .bold)).foregroundColor(C.ink)
            Spacer()
            if !right.isEmpty { Text(right).font(.mylo(14)).foregroundColor(C.teal) }
            if chevron { Image(systemName: "chevron.down").font(.mylo(13)).foregroundColor(C.teal) }
        }
        .padding(.top, 18).padding(.bottom, 4)
    }

    private func rating(_ ms: Int?) -> some View {
        let qv = quality(ms)
        return HStack(spacing: 8) {
            if let ms { Text("\(ms) ms").font(.mylo(13)).foregroundColor(C.muted) }
            Text(qv.label).font(.mylo(17)).foregroundColor(C.teal)
            SignalBars(level: qv.bars)
        }
    }

    private func fastestRow(_ best: Server) -> some View {
        Button { Store.shared.activeOvpn = ""; vm.setAuto(true); onBack() } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text(flagEmoji(best.cc)).font(.mylo(26))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Fastest Location").font(.mylo(20, weight: vm.auto ? .bold : .regular))
                            .foregroundColor(vm.auto ? C.teal : C.ink)
                        Text(best.name).font(.mylo(13)).foregroundColor(C.muted).lineLimit(1)
                    }
                    Spacer()
                    rating(best.pingMs)
                }
                .frame(minHeight: 62)
                divider
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ s: Server, compact: Bool, detail: Bool, fav: Bool, delete: Bool) -> some View {
        let selected = !vm.auto && s.address == vm.selected
        let isFav = vm.favs.contains(s.address)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { pick(s) } label: {
                    HStack(spacing: 14) {
                        Text(flagEmoji(s.cc)).font(.mylo(26))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).font(.mylo(20, weight: selected ? .bold : .regular))
                                .foregroundColor(selected ? C.teal : C.ink).lineLimit(1)
                        }
                        Spacer()
                        if let ms = s.pingMs {
                            if compact { Text("\(ms)ms").font(.mylo(17)).foregroundColor(C.muted) } else { rating(ms) }
                        } else if s.pinged {
                            Text("timeout").font(.mylo(13)).foregroundColor(C.danger)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if fav {
                    Button { vm.toggleFav(s.address) } label: {
                        Image(systemName: isFav ? "heart.fill" : "heart").foregroundColor(isFav ? C.pink : C.muted)
                    }
                }
                if delete {
                    Button { vm.removeServer(s.address) } label: { Image(systemName: "trash").foregroundColor(C.muted) }
                }
            }
            .frame(minHeight: 56)
            divider
        }
    }
}

struct AddServerSheet: View {
    @EnvironmentObject var vm: VpnViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var n = ""
    @State private var a = ""
    @State private var c = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (optional)", text: $n)
                TextField("Address / hostname", text: $a)
#if canImport(UIKit)
                        .autocapitalization(.none)
#endif
                        .autocorrectionDisabled()
                TextField("Country code (auto if empty)", text: $c)
#if canImport(UIKit)
                        .autocapitalization(.allCharacters)
#endif
                        .autocorrectionDisabled()
                        .onValueChange(of: c) { v in if v.count > 2 { c = String(v.prefix(2)) } }
            }
            .navigationTitle("Add server")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { vm.addServer(name: n, address: a, cc: c); dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ImportSheet: View {
    @EnvironmentObject var vm: VpnViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var t = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("One per line:  name|address|cc").font(.footnote).foregroundColor(.secondary)
                TextEditor(text: $t)
                    .font(.system(.footnote, design: .monospaced))
#if canImport(UIKit)
                    .autocapitalization(.none)
#endif
                    .autocorrectionDisabled()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
                Button("Paste from clipboard") {
                    #if canImport(UIKit)
                    if let pasteString = UIPasteboard.general.string {
                        t = pasteString
                    }
                    #elseif canImport(AppKit)
                    if let pasteString = NSPasteboard.general.string(forType: .string) {
                        t = pasteString
                    }
                    #endif
                }
            }
            .padding()
            .navigationTitle("Import server list")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import") { vm.importText(t); dismiss() } }
            }
        }
    }
}
