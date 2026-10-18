import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Combine

@MainActor
final class VpnViewModel: ObservableObject {
    let store = Store.shared
    let vpn = VpnController.shared
    let speed = SpeedTest()

    @Published var servers: [Server] = []
    @Published var selected = ""
    @Published var auto = false
    @Published var pinging = false
    @Published var favs: Set<String> = []
    @Published var history: [Hist] = []
    @Published var live = LiveInfo()
    @Published var showIp = true
    @Published var failover = true
    @Published var verify = true
    @Published var killSwitch = false
    @Published var theme = "System"
    @Published var toast: String?

    private var prep: Task<Void, Never>?
    private var lastPing = Date.distantPast
    private var bag = Set<AnyCancellable>()

    init() {
        store.migrate()
        if !Defaults.requireLogin { store.seedAccountFromDefaults() }
        servers = store.servers()
        selected = store.current
        auto = store.autoSelect
        favs = store.favorites()
        history = store.history()
        showIp = store.showIp
        failover = store.failover
        verify = store.verify
        killSwitch = store.killSwitch
        theme = store.theme
        vpn.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        speed.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        vpn.startWatching()
        Task { await vpn.restore() }
        #if OPENVPN
        Task { await OpenVPNController.shared.restore() }
        #endif
    }

    // MARK: forwarded controller state
    var state: VpnController.State { vpn.state }
    var lines: [String] { vpn.lines }
    var detail: String { vpn.detail }
    var stats: Stats { vpn.stats }
    var mode: VpnController.Mode { vpn.mode }
    var notice: String { vpn.notice }

    var connectedInfo: (server: String, since: Date, ip: String?)? {
        if case let .connected(s, since, ip) = vpn.state { return (s, since, ip) }
        return nil
    }
    var isConnected: Bool { connectedInfo != nil }
    var isConnecting: Bool { if case .connecting = vpn.state { return true }; return false }
    var failedMessage: String? { if case let .failed(m) = vpn.state { return m }; return nil }
    var isActive: Bool { isConnected || isConnecting }

    func say(_ m: String) {
        toast = m
        Task { try? await Task.sleep(nanoseconds: 2_800_000_000); if toast == m { toast = nil } }
    }

    // MARK: settings
    func setTheme(_ n: String) { theme = n; store.theme = n }
    func setShowIp(_ v: Bool) { showIp = v; store.showIp = v; if v && isConnected { vpn.fetchPublicIp() } }
    func setFailover(_ v: Bool) { failover = v; store.failover = v }
    func setVerify(_ v: Bool) { verify = v; store.verify = v }
    func setKillSwitch(_ v: Bool) { killSwitch = v; store.killSwitch = v }

    // MARK: servers
    func addServer(name: String, address: String, cc: String) {
        let a = address.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        if a.isEmpty { say("Enter a server address"); return }
        if servers.contains(where: { $0.address == a }) { say("Server already exists"); return }
        let n = name.trimmingCharacters(in: .whitespaces)
        let c = cc.trimmingCharacters(in: .whitespaces).uppercased()
        update(servers + [Server(name: n.isEmpty ? a : n, address: a, cc: c.isEmpty ? guessCc(a) : c)])
    }

    func removeServer(_ address: String) {
        update(servers.filter { $0.address != address })
        if selected == address { select("") }
    }

    func importText(_ text: String) {
        let add = ListParser.parse(text).filter { n in !servers.contains { $0.address == n.address } }
        update(servers + add)
        say("\(add.count) server(s) added")
    }

    private func update(_ l: [Server]) { servers = l; store.saveServers(l) }

    func select(_ address: String) {
        store.activeOvpn = ""        // an IKEv2 location replaces any selected OpenVPN profile
        selected = address
        store.current = address
        setAuto(false)
    }

    func setAuto(_ v: Bool) { auto = v; store.autoSelect = v }

    func toggleFav(_ address: String) { favs = store.toggleFavorite(address) }
    func refreshHistory() { history = store.history() }

    // MARK: pings
    func pingAll() {
        if pinging { return }
        Task { await pingInternal() }
    }

    /// Measures every server and updates the list as each answer arrives.
    /// While the VPN is on the probes would travel through the tunnel and show wrong numbers, so they pause.
    private func pingInternal() async {
        if isConnected { return }
        pinging = true
        _ = await Pinger.pingAll(servers, progress: { [weak self] addr, ms in
            guard let self, let i = self.servers.firstIndex(where: { $0.address == addr }) else { return }
            self.servers[i].pingMs = ms
            self.servers[i].pinged = true
        }, note: { [weak self] m in self?.vpn.log(m) })
        pinging = false
        lastPing = Date()
    }

    /// Runs while a screen is visible: re-measures everything every few seconds (cancelled with the view).
    func livePingLoop(_ period: Double = 4) async {
        while !Task.isCancelled {
            if !pinging && !isConnecting { await pingInternal() }
            try? await Task.sleep(nanoseconds: UInt64(period * 1_000_000_000))
        }
    }

    /// One live-ping sample: direct (real connection, only while the VPN is off) and through the tunnel.
    func measureLiveOnce() async {
        let connected = isConnected
        let direct: Int? = connected ? nil : await LivePing.direct()
        let viaVpn: Int? = connected ? await LivePing.vpn() : nil
        live = LiveInfo(directMs: direct, vpnMs: viaVpn)
    }

    func liveLoop() async {
        while !Task.isCancelled {
            await measureLiveOnce()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    // MARK: connect
    private func pickServer() async -> Server? {
        var s = servers.first { $0.address == selected }
        if auto || s == nil {
            if Date().timeIntervalSince(lastPing) > 60 {
                vpn.log("measuring servers...")
                await pingInternal()
            }
            s = servers.filter { $0.pingMs != nil }.min { $0.pingMs! < $1.pingMs! } ?? s ?? servers.first
        }
        return s
    }

    func toggle() {
        #if OPENVPN
        if !store.activeOvpn.isEmpty { toggleOpenVPN(); return }
        #endif
        #if !APPSTORE
        if mode == .profile { toggleProfile(); return }
        #endif
        if isActive { prep?.cancel(); vpn.disconnect(); return }
        if store.user.isEmpty || store.pass.isEmpty {
            vpn.fail("No IKEv2 account. Enter it in Profile > Advanced."); return
        }
        vpn.markBusy()
        prep = Task {
            guard let chosen = await pickServer() else { vpn.fail("No servers - add one in Locations"); return }
            if Task.isCancelled { return }
            selected = chosen.address
            var fb = servers.filter { $0.address != chosen.address }
            if auto { fb = fb.filter { $0.pingMs != nil }.sorted { $0.pingMs! < $1.pingMs! } }
            vpn.connect(chosen, fallbacks: Array(fb.prefix(3)))
        }
    }

    /// A .ovpn file opened with MYLO (Files, Share sheet, a provider's download): save it, make it the active
    /// profile and connect straight away with the built-in engine, without going through any other app.
    func openOvpnFile(_ url: URL) {
        #if !APPSTORE
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { say("Could not read the .ovpn file"); return }
        do {
            let p = try ConfigParser.parseOvpn(text, filename: url.lastPathComponent)
            ConfigStore.add(p)
            guard let id = ConfigStore.id(forRaw: p.raw) else { return }
            #if OPENVPN
            store.activeOvpn = id
            if ConfigParser.needsAuth(p.raw) && ConfigStore.auth(id) == nil && ConfigStore.inheritAuth(for: id) == nil {
                say("Saved. Add the username and password in Profile > Add configuration, then tap the power button.")
                return
            }
            if !isActive { toggleOpenVPN() }
            #else
            say("Saved. OpenVPN connects only in the MYLO-OpenVPN build.")
            #endif
        } catch { say(error.localizedDescription) }
        #endif
    }

    #if !APPSTORE
    #if OPENVPN
    // MARK: OpenVPN profile selected in Add configuration
    private func toggleOpenVPN() {
        if isActive { prep?.cancel(); OpenVPNController.shared.disconnect(); return }
        guard let cfg = ConfigStore.list().first(where: { $0.id == store.activeOvpn }), let raw = ConfigStore.raw(cfg.id) else {
            store.activeOvpn = ""
            vpn.fail("The selected OpenVPN profile no longer exists."); return
        }
        let auth = ConfigStore.auth(cfg.id)
        if ConfigParser.needsAuth(raw) && auth == nil {
            vpn.fail("This OpenVPN profile needs a username and password: Profile > Add configuration > Login."); return
        }
        vpn.markBusy()
        prep = Task {
            do { try await OpenVPNController.shared.connect(cfg, raw: raw, auth: auth) }
            catch { vpn.fail(error.localizedDescription) }
        }
    }
    #endif

    // MARK: profile mode (free Apple ID)
    // One VPN entry ("MYLO VPN") in Settings. Installing a profile is only needed the first time or after the
    // location/account changed. Turning it on/off is done by running the user's Shortcuts ("Set VPN"), which is
    // the only way iOS lets an app without the Personal VPN entitlement switch a VPN on.
    private func shortcutURL(_ name: String) -> URL? {
        let n = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "shortcuts://x-callback-url/run-shortcut?name=\(n)&x-success=mylo://done&x-cancel=mylo://done&x-error=mylo://done")
    }

    private func runShortcut(_ name: String) async -> Bool {
        guard let u = shortcutURL(name) else { return false }
        #if canImport(UIKit)
        return await UIApplication.shared.open(u)
        #elseif canImport(AppKit)
        return NSWorkspace.shared.open(u)
        #endif
    }

    private func sendProfile(_ chosen: Server, replacing: Bool) async {
        vpn.log("installing VPN profile for \(chosen.name)")
        let ok = await ProfileInstaller.install(server: chosen)
        if ok {
            store.profileSent = ProfileExport.fingerprint([chosen])
            // Installing a profile does NOT connect anything: the state stays "Not Protected".
            vpn.setNotice((replacing ? "Location changed: the MYLO VPN entry will be replaced. " : "")
                          + "Install the profile in Settings, then come back and tap the power button again.")
        }
        say(ok ? "Allow in Safari, install in Settings, then tap power again" : "Could not open the installer. Try again.")
    }

    private func toggleProfile() {
        if isConnecting { return }
        if isConnected {
            if store.shortcutsReady {
                Task { _ = await runShortcut(Defaults.shortcutOff) }
            } else {
                say("Switch the VPN off in Settings > VPN")
                Diag.openVpnSettings()
            }
            return
        }
        vpn.clearFailure()
        if store.user.isEmpty || store.pass.isEmpty { vpn.fail("No IKEv2 account. Enter it in Profile > Advanced."); return }
        prep?.cancel()
        prep = Task {
            // With "fastest location" on, keep the already installed server instead of reinstalling the profile
            // every time the fastest one changes.
            var pick: Server? = nil
            if auto, !store.profileSent.isEmpty { pick = servers.first { $0.address == store.current } }
            if pick == nil { pick = await pickServer() }
            guard let chosen = pick else { vpn.fail("No servers - add one in Locations"); return }
            selected = chosen.address
            let hadProfile = !store.profileSent.isEmpty
            store.current = chosen.address
            if store.profileSent != ProfileExport.fingerprint([chosen]) {
                await sendProfile(chosen, replacing: hadProfile)
                return
            }
            guard store.shortcutsReady else {
                vpn.setNotice("One-time setup: create the shortcuts \"\(Defaults.shortcutOn)\" and \"\(Defaults.shortcutOff)\" (Profile > Advanced > One-tap connect). After that this button turns the VPN on and off.")
                say("Set up the shortcuts first (Profile > Advanced)")
                return
            }
            vpn.beginProfileConnect()
            if await !runShortcut(Defaults.shortcutOn) {
                vpn.cancelProfileConnect("Could not open the Shortcuts app.")
            }
        }
    }

    /// Forces a fresh install/update of the profile (Profile > Advanced).
    func installProfileNow() {
        Task {
            guard let chosen = await pickServer() else { say("No servers"); return }
            selected = chosen.address
            store.current = chosen.address
            await sendProfile(chosen, replacing: !store.profileSent.isEmpty)
        }
    }

    func openShortcutsApp() {
        #if canImport(UIKit)
        if let u = URL(string: "shortcuts://") { UIApplication.shared.open(u) }
        #elseif canImport(AppKit)
        if let u = URL(string: "shortcuts://") { NSWorkspace.shared.open(u) }
        #endif
    }
    #endif

    /// Called after logout: the VPN account is gone, so the tunnel must go too.
    func onLogout() {
        prep?.cancel()
        if mode == .native && isActive { vpn.disconnect() }
        vpn.clearFailure()
    }
}
