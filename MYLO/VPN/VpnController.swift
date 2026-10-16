import Foundation
import NetworkExtension
import Combine

/// Port of VpnController.kt.
///  * native mode  : the app owns the tunnel (NEVPNManager, needs the Personal VPN entitlement of a paid account).
///  * profile mode : no entitlement (free Apple ID). The tunnel is an iOS VPN profile switched on in Settings > VPN;
///                   the app only watches the tunnel interface (status, speed, usage) and installs the profile.
@MainActor
final class VpnController: ObservableObject {
    static let shared = VpnController()

    enum State: Equatable {
        case disconnected
        /// attempt == 0 means "preparing / reconnecting"
        case connecting(server: String, attempt: Int, total: Int)
        case connected(server: String, since: Date, ip: String?)
        case failed(String)
    }

    enum Mode { case native, profile }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var lines: [String] = []
    /// One-line progress / last error shown under the status while connecting.
    @Published private(set) var detail = ""
    @Published var stats = Stats()
    /// Guidance shown under the status in profile mode (never changes `state`).
    @Published private(set) var notice = ""

    var mode: Mode {
        #if APPSTORE
        return .native     // App Store build: always the app-owned tunnel (Personal VPN entitlement)
        #else
        return Diag.hasVpnEntitlement() == false ? .profile : .native
        #endif
    }

    private let store = Store.shared
    private var manager: NEVPNManager { NEVPNManager.shared() }
    private var job: Task<Void, Never>?
    private var watchJob: Task<Void, Never>?
    private var want = false
    private var lastError: String?
    private var since = Date()
    private var histServer: Server?
    private var histStart = Date()
    private var lastStatus: NEVPNStatus = .invalid
    private var connectGuard: Task<Void, Never>?
    private static let attemptTimeout: TimeInterval = 20

    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private init() {
        NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.statusChanged() }
        }
    }

    private var up: Bool { manager.connection.status == .connected }

    /// What is allowed to prove that a VPN is really running:
    ///  * nativeStatus : NEVPNManager reports `.connected` for the tunnel this app configured itself.
    ///  * routeProof   : (profile mode only) iOS sends ordinary internet traffic out through a tunnel interface
    ///                   and that stayed true for two consecutive samples. See `NetIf.vpn()`.
    /// NOT evidence: an installed profile, a utun/ipsec interface merely existing (even with an IP), internet
    /// being reachable, ping or TCP probes succeeding.
    enum Evidence: String { case nativeStatus, routeProof }

    /// The ONLY place in the app that may assign `.connected` to `state`.
    private func declareConnected(server: String, since: Date, ip: String?, source: Evidence) {
        let new = State.connected(server: server, since: since, ip: ip)
        if state != new { log("state -> connected (evidence: \(source.rawValue))") }
        state = new
        detail = ""
        notice = ""
        connectGuard?.cancel()
    }

    /// Profile mode: the Shortcut was launched. "Connecting" is shown, but `.connected` still only comes from
    /// route proof; if nothing shows up within 25 s the state goes back to Not Protected.
    func beginProfileConnect() {
        state = .connecting(server: "MYLO VPN", attempt: 0, total: 0)
        detail = "Turning on VPN through Shortcuts..."
        notice = ""
        connectGuard?.cancel()
        connectGuard = Task {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            if Task.isCancelled { return }
            if case .connecting = state {
                cancelProfileConnect("The VPN did not turn on. Check the \"\(Defaults.shortcutOn)\" shortcut in Profile > Advanced.")
            }
        }
    }

    func cancelProfileConnect(_ message: String) {
        connectGuard?.cancel()
        if case .connecting = state { state = .disconnected }
        detail = ""
        notice = message
    }

    func setNotice(_ text: String) { notice = text }

    /// OpenVPN (Network Extension) status. NETunnelProviderManager is the evidence, like NEVPNManager.
    func openVPNStatus(_ s: NEVPNStatus, name: String, since: Date?, error: String?) {
        switch s {
        case .connected:
            let t = since ?? Date()
            self.since = t
            histServer = Server(name: name, address: "", cc: ""); histStart = t
            declareConnected(server: name, since: t, ip: NetIf.vpn().ip, source: .nativeStatus)
            fetchPublicIp(); measureLatency()
        case .connecting, .reasserting:
            detail = "OpenVPN: \(name)"
            state = .connecting(server: name, attempt: 0, total: 0)
        case .disconnected, .invalid:
            endHistory("Disconnected")
            if let e = error { fail("OpenVPN: \(e)") } else { state = .disconnected; detail = "" }
        case .disconnecting:
            break
        @unknown default:
            break
        }
    }

    private func statusChanged() {
        guard mode == .native else { return }
        let s = manager.connection.status
        guard s != lastStatus else { return }
        lastStatus = s
        log("system VPN status: \(Self.statusName(s))")
    }

    private static func statusName(_ s: NEVPNStatus) -> String {
        switch s {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }

    private static func errorText(_ e: NSError) -> String {
        guard e.domain == "NEVPNConnectionErrorDomain" else { return "\(e.domain) \(e.code): \(e.localizedDescription)" }
        let n: String
        switch e.code {
        case 2: n = "no network available"
        case 3: n = "unrecoverable network change"
        case 5: n = "server address resolution failed (DNS)"
        case 6: n = "server not responding - UDP 500/4500 blocked or wrong host"
        case 7: n = "server dead (DPD)"
        case 8: n = "AUTHENTICATION FAILED (wrong VPN account or remote ID)"
        case 15: n = "negotiation failed (cipher / ID mismatch)"
        case 16: n = "server disconnected"
        case 17: n = "server certificate invalid (is the CA installed and trusted?)"
        case 18: n = "server certificate not yet valid"
        case 19: n = "server certificate expired"
        default: n = e.localizedDescription
        }
        return "IKE error \(e.code): \(n)"
    }

    private static func setupError(_ error: Error) -> String {
        let e = error as NSError
        let denied = e.localizedDescription.lowercased().contains("permission denied")
            || (e.domain == "NEVPNErrorDomain" && e.code == 5)
        guard denied else { return "\(e.localizedDescription) [\(e.domain) \(e.code)]" }
        return "iOS refused to save the VPN configuration. If you tapped \"Don't Allow\" earlier, delete the app, install it again and tap Allow."
    }

    // MARK: logging / state helpers
    func log(_ m: String) {
        lines = Array((lines + ["\(timeFmt.string(from: Date()))  \(m)"]).suffix(300))
    }

    func fail(_ msg: String) {
        want = false
        endHistory("Failed")
        log("FAILED: \(msg)")
        state = .failed(msg)
    }

    func markBusy() {
        detail = "Preparing..."
        state = .connecting(server: "", attempt: 0, total: 0)
    }

    func clearFailure() { if case .failed = state { state = .disconnected } }

    // MARK: profile mode: observe whether iOS really routes traffic through a tunnel
    // A profile installed from Settings is invisible to this app (NEVPNManager only exposes configurations the app
    // created itself, and that needs the Personal VPN entitlement). So the state is never taken from the profile,
    // it stays "disconnected" until the routing evidence below holds, and goes back as soon as it stops holding.
    func startWatching() {
        guard mode == .profile, watchJob == nil else { return }
        log("device: iOS profile mode (no Personal VPN entitlement) - status is only taken from real routing evidence")
        watchJob = Task { await watchLoop() }
    }

    private func watchLoop() async {
        var wasUp = false
        var upStreak = 0, downStreak = 0
        var lastRx: UInt32 = 0, lastTx: UInt32 = 0
        var totRx: Int64 = 0, totTx: Int64 = 0
        var pendRx: Int64 = 0, pendTx: Int64 = 0
        var pendSec = 0.0
        var lastTick = Date()
        var tick = 0
        while !Task.isCancelled {
            let snap = Defaults.profileAutoDetect ? NetIf.vpn() : NetIf.Snapshot()
            let routed = snap.ip != nil
            if routed { upStreak += 1; downStreak = 0 } else { downStreak += 1; upStreak = 0 }
            let now = Date()

            if !wasUp {
                if upStreak >= 2 {          // two consecutive samples, so one odd sample cannot flip the state
                    wasUp = true
                    since = now; lastTick = now
                    lastRx = snap.rx; lastTx = snap.tx
                    totRx = 0; totTx = 0; pendRx = 0; pendTx = 0; pendSec = 0; tick = 0
                    stats = Stats()
                    // Profile mode: the user picks the entry in Settings, so the app cannot know which location it is.
                    let srv = Server(name: "MYLO VPN", address: "", cc: "")
                    histServer = srv; histStart = now
                    declareConnected(server: srv.name, since: now, ip: snap.ip, source: .routeProof)
                    log("traffic now leaves through \(snap.name ?? "tunnel") (\(snap.ip ?? "?"))")
                    fetchPublicIp(); measureLatency()
                }
            } else if routed {
                let dt = max(now.timeIntervalSince(lastTick), 1)
                lastTick = now
                let dr = Self.delta(snap.rx, lastRx), du = Self.delta(snap.tx, lastTx)
                lastRx = snap.rx; lastTx = snap.tx
                totRx += dr; totTx += du; pendRx += dr; pendTx += du; pendSec += dt
                var st = stats
                st.downBps = Int64(Double(dr) / dt); st.upBps = Int64(Double(du) / dt)
                st.rx = totRx; st.tx = totTx
                st.downHist = Array((st.downHist + [st.downBps]).suffix(60))
                st.upHist = Array((st.upHist + [st.upBps]).suffix(60))
                stats = st
                tick += 1
                if tick % 10 == 0 {
                    let whole = Int(pendSec)
                    store.addSeconds(whole); pendSec -= Double(whole)
                    store.addBytes(rx: pendRx, tx: pendTx); pendRx = 0; pendTx = 0
                    measureLatency()
                }
            } else if downStreak >= 2 {
                wasUp = false
                endHistory("Disconnected")
                state = .disconnected
                stats = Stats()
                log("traffic no longer goes through a tunnel - VPN is off")
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        watchJob = nil
    }

    // MARK: native mode: attach to a tunnel that is already running (app was relaunched)
    func restore() async {
        guard mode == .native else { return }
        try? await manager.loadFromPreferences()
        let s = manager.connection.status
        guard s == .connected || s == .connecting || s == .reasserting, state == .disconnected else { return }
        let addr = manager.protocolConfiguration?.serverAddress ?? ""
        let srv = store.servers().first { $0.address == addr } ?? Server(name: "MYLO VPN", address: addr, cc: guessCc(addr))
        want = true
        since = manager.connection.connectedDate ?? Date()
        histServer = srv; histStart = since
        lastStatus = s
        log("attached to running tunnel: \(addr)")
        if s == .connected {
            declareConnected(server: srv.name, since: since, ip: NetIf.vpn().ip, source: .nativeStatus)
        } else {
            state = .connecting(server: srv.name, attempt: 0, total: 0)
        }
        job = Task { await monitor(srv) }
    }

    // MARK: native mode: connect / disconnect
    func connect(_ s: Server, fallbacks: [Server] = []) {
        job?.cancel()
        job = Task { await runChain([s] + fallbacks) }
    }

    func disconnect() {
        want = false
        job?.cancel(); job = nil
        if mode == .native { manager.connection.stopVPNTunnel() }
        endHistory("Disconnected")
        state = .disconnected
        detail = ""
        log("disconnected")
    }

    /// Try the chosen server (3 variants), then fall through to the next servers (1 try each).
    private func runChain(_ chain: [Server]) async {
        want = true
        lastError = nil
        log("device: iOS native mode, kill switch=\(store.killSwitch), verify=\(store.verify)")
        await stopTunnel()
        try? await Task.sleep(nanoseconds: 400_000_000)
        for (idx, s) in chain.enumerated() {
            if Task.isCancelled || !want { return }
            store.current = s.address
            if await tryServer(s, attempts: idx == 0 ? 3 : 1) { await monitor(s); return }
            if Task.isCancelled || !want { return }
            log("giving up on \(s.name)")
        }
        fail("Could not connect to any server" + (lastError.map { " - last error: \($0)" } ?? "."))
    }

    private func stopTunnel() async {
        let st = manager.connection.status
        if st == .disconnected || st == .invalid { return }
        manager.connection.stopVPNTunnel()
        for _ in 0..<25 {
            if manager.connection.status == .disconnected { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func awaitUp() async -> Bool {
        let begin = Date()
        var sawActivity = false
        while Date().timeIntervalSince(begin) < Self.attemptTimeout {
            if Task.isCancelled || !want { return false }
            switch manager.connection.status {
            case .connected:
                return true
            case .connecting, .reasserting:
                sawActivity = true
            case .disconnected, .invalid:
                if sawActivity || Date().timeIntervalSince(begin) > 3 { await captureError(); return false }
            default: break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func captureError() async {
        guard #available(iOS 16.0, *) else { return }
        let err: Error? = await withCheckedContinuation { c in
            manager.connection.fetchLastDisconnectError { c.resume(returning: $0) }
        }
        if let e = err as NSError? {
            let m = Self.errorText(e)
            log(m); lastError = m
        }
    }

    private static let probeTargets: [(String, UInt16)] = [("1.1.1.1", 443), ("8.8.8.8", 443), ("9.9.9.9", 443), ("www.cloudflare.com", 443)]

    /// True if at least one of several well-known endpoints answers. This only shows that the internet works.
    /// It is a health check for a tunnel NEVPNManager already reports as connected, never proof of a VPN.
    private func probeTunnel() async -> Bool {
        for (h, p) in Self.probeTargets {
            if await Probe.tcpLatency(host: h, port: p) != nil { return true }
        }
        return false
    }

    private func validateTunnel() async -> Bool {
        let end = Date().addingTimeInterval(9)
        while Date() < end {
            if Task.isCancelled || !want { return false }
            if await probeTunnel() { return true }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        return false
    }

    private func tryServer(_ s: Server, attempts: Int) async -> Bool {
        for n in 0..<attempts {
            if Task.isCancelled || !want { return false }
            let variant = attempts == 1 ? 1 : n
            state = .connecting(server: s.name, attempt: n + 1, total: attempts)
            detail = "\(s.name) - try \(n + 1)/\(attempts)" + (lastError.map { "\n\($0)" } ?? "")
            log("connecting to \(s.name) (try \(n + 1)/\(attempts): \(describe(variant)))")
            do {
                try await configure(s, variant: variant)
                try manager.connection.startVPNTunnel()
            } catch {
                fail(Self.setupError(error))
                return false
            }
            if await awaitUp() {
                log("tunnel up (virtual IP \(NetIf.vpn().ip ?? "?"))")
                detail = "Checking connection..."
                var verified = true
                if store.verify { verified = await validateTunnel() }
                if verified && up {          // NEVPNManager must still say "connected" at this very moment
                    since = Date()
                    histServer = s; histStart = since
                    declareConnected(server: s.name, since: since, ip: NetIf.vpn().ip, source: .nativeStatus)
                    log("connection verified - tunnel is up and traffic passes")
                    return true
                }
                if !want || Task.isCancelled { return false }
                log("tunnel dropped or NO traffic passes (option \(variant + 1)) - trying the next option")
                await stopTunnel()
                continue
            }
            if !want || Task.isCancelled { return false }
            log("try \(n + 1) failed" + (lastError.map { ": \($0)" } ?? " / timed out"))
            await stopTunnel()
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        return false
    }

    private func describe(_ i: Int) -> String {
        switch i {
        case 0: return "aes256-sha256-modp2048, unique local id"
        case 1: return "aes256-sha256-modp2048 IKE + aes256gcm child, unique local id"
        default: return "aes256-sha256-modp2048, username as local id"
        }
    }

    // MARK: native mode: monitor / stats / history
    private func endHistory(_ status: String) {
        guard let s = histServer else { return }
        histServer = nil
        store.addHistory(Hist(server: s.name, cc: s.cc, start: histStart.timeIntervalSince1970,
                              end: Date().timeIntervalSince1970, rx: stats.rx, tx: stats.tx, status: status))
    }

    /// Asks api.ipify.org for the public IP. Only done when "Show IP" is on, so by default no third party is contacted.
    func fetchPublicIp() {
        guard store.showIp else { return }
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://api.ipify.org")!)
                req.timeoutInterval = 8
                let (d, _) = try await URLSession.shared.data(for: req)
                stats.publicIp = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch { log("public IP lookup failed: \(error.localizedDescription)") }
        }
    }

    private func measureLatency() {
        Task {
            if let ms = await Probe.tcpLatency(host: "1.1.1.1", port: 443) { stats.latencyMs = ms }
        }
    }

    private static func delta(_ new: UInt32, _ old: UInt32) -> Int64 {
        if new >= old { return Int64(new - old) }
        if old > 0xC000_0000 { return Int64(UInt32.max - old) + Int64(new) + 1 }   // 32-bit counter wrapped
        return Int64(new)                                                           // interface was re-created
    }

    private func waitUp(timeout: TimeInterval) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if Task.isCancelled || !want { return false }
            if up, await probeTunnel() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    /// Port of the Android monitor: liveness check, failover, usage accounting. Conservative: the tunnel is only
    /// called dead after ~10 s without inbound traffic AND three failed probes.
    private func monitor(_ s: Server) async {
        let base = NetIf.vpn()
        var lastRx = base.rx, lastTx = base.tx
        var totRx: Int64 = 0, totTx: Int64 = 0
        var pendRx: Int64 = 0, pendTx: Int64 = 0, pendSec = 0.0
        var lastTick = Date()
        var lastRxAt = Date()
        var fails = 0
        var tick = 0
        stats = Stats()
        detail = ""
        fetchPublicIp(); measureLatency()

        while want && !Task.isCancelled {
            if up && fails < 3 {
                if case .connected = state {} else {
                    declareConnected(server: s.name, since: since, ip: NetIf.vpn().ip, source: .nativeStatus)
                    lastTick = Date()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || !want { return }
                let snap = NetIf.vpn()
                let now = Date()
                let dt = max(now.timeIntervalSince(lastTick), 1)
                lastTick = now
                let dr = Self.delta(snap.rx, lastRx), du = Self.delta(snap.tx, lastTx)
                lastRx = snap.rx; lastTx = snap.tx
                totRx += dr; totTx += du; pendRx += dr; pendTx += du; pendSec += dt
                var st = stats
                st.downBps = Int64(Double(dr) / dt); st.upBps = Int64(Double(du) / dt)
                st.rx = totRx; st.tx = totTx
                st.downHist = Array((st.downHist + [st.downBps]).suffix(60))
                st.upHist = Array((st.upHist + [st.upBps]).suffix(60))
                stats = st
                if st.downBps > 2000 { lastRxAt = now; fails = 0 }
                tick += 1
                if tick % 5 == 0 && now.timeIntervalSince(lastRxAt) > 10 {
                    if await probeTunnel() { fails = 0; lastRxAt = Date() }
                    else { fails += 1; log("no traffic for 10 s and probe failed (\(fails)/3)") }
                }
                if tick % 10 == 0 {
                    let whole = Int(pendSec)
                    store.addSeconds(whole); pendSec -= Double(whole)
                    store.addBytes(rx: pendRx, tx: pendTx); pendRx = 0; pendTx = 0
                    measureLatency()
                }
            } else {
                detail = "Reconnecting..."
                state = .connecting(server: s.name, attempt: 0, total: 0)
                let back = await waitUp(timeout: 15)
                if !want || Task.isCancelled { return }
                if back { fails = 0; lastRxAt = Date(); lastTick = Date(); continue }

                log("connection lost: \(s.name)")
                await captureError()
                endHistory("Connection lost")
                await stopTunnel()    // give the phone its normal internet back
                if store.failover {
                    let others = store.servers().filter { $0.address != s.address }
                    let best = await Pinger.pingAll(others).filter { $0.pingMs != nil }.min { $0.pingMs! < $1.pingMs! }
                    if let n = best { log("failover -> \(n.name)"); connect(n); return }
                }
                want = false
                state = .failed("VPN dropped - normal internet restored")
                log("VPN stopped so normal internet works again")
                return
            }
        }
    }

    // MARK: native mode: profile builder
    private func configure(_ s: Server, variant: Int) async throws {
        let user = store.user
        let p = NEVPNProtocolIKEv2()
        p.serverAddress = s.address
        p.remoteIdentifier = store.remoteId.isEmpty ? Defaults.rid : store.remoteId
        p.localIdentifier = variant >= 2 ? user : store.localId()
        p.authenticationMethod = .none            // server auth by certificate, client auth by EAP (username/password)
        p.useExtendedAuthentication = true
        p.username = user
        p.passwordReference = Keychain.persistentRef("vpnpass")
        p.disconnectOnSleep = false
        p.deadPeerDetectionRate = .medium
        if !store.issuerCN.isEmpty { p.serverCertificateIssuerCommonName = store.issuerCN }
        p.includeAllNetworks = store.killSwitch   // iOS kill switch
        p.excludeLocalNetworks = true

        // Current iOS refuses SHA-1 and DH groups below 14, so only modern proposals are used.
        let ike = p.ikeSecurityAssociationParameters
        let child = p.childSecurityAssociationParameters
        ike.encryptionAlgorithm = .algorithmAES256; ike.integrityAlgorithm = .SHA256; ike.diffieHellmanGroup = .group14
        switch variant {
        case 1:   // AEAD child SA (AES-256-GCM; AES-128-GCM is deprecated since iOS 17)
            child.encryptionAlgorithm = .algorithmAES256GCM; child.diffieHellmanGroup = .group14
        default:  // aes256-sha256-modp2048 (variant 2 differs only by the local id above)
            child.encryptionAlgorithm = .algorithmAES256; child.integrityAlgorithm = .SHA256; child.diffieHellmanGroup = .group14
        }

        try await manager.loadFromPreferences()
        manager.protocolConfiguration = p
        manager.localizedDescription = "MYLO VPN"
        manager.isEnabled = true
        manager.isOnDemandEnabled = false
        try await manager.saveToPreferences()      // first time: iOS shows the "Add VPN Configurations" prompt
        try await manager.loadFromPreferences()    // required before startVPNTunnel after a save
    }
}
