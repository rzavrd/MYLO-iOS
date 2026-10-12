import Foundation
import Security

/// Small Keychain wrapper (login session + VPN password live here, never in UserDefaults).
enum Keychain {
    private static let service = "com.mylo.vpn"

    private static func base(_ k: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: k]
    }

    static func get(_ k: String) -> String? {
        var q = base(k)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ k: String, _ v: String) {
        SecItemDelete(base(k) as CFDictionary)
        guard !v.isEmpty else { return }
        var q = base(k)
        q[kSecValueData as String] = Data(v.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ k: String) { SecItemDelete(base(k) as CFDictionary) }

    /// Persistent reference, as required by NEVPNProtocol.passwordReference.
    static func persistentRef(_ k: String) -> Data? {
        var q = base(k)
        q[kSecReturnPersistentRef as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}

/// App settings. The VPN username/password are filled in by the login (Auth.swift), not by the user.
final class Store {
    static let shared = Store()
    private let d = UserDefaults.standard
    private init() {}

    private func str(_ k: String, _ def: String = "") -> String { d.string(forKey: "mylo_" + k) ?? def }
    private func put(_ k: String, _ v: Any?) { d.set(v, forKey: "mylo_" + k) }

    var user: String { get { str("user") } set { put("user", newValue) } }
    var pass: String { get { Keychain.get("vpnpass") ?? "" } set { Keychain.set("vpnpass", newValue) } }
    var remoteId: String { get { str("rid", Defaults.rid) } set { put("rid", newValue) } }
    var issuerCN: String { get { str("issuer") } set { put("issuer", newValue) } }
    var current: String { get { str("cur") } set { put("cur", newValue) } }
    var theme: String { get { str("theme", "System") } set { put("theme", newValue) } }
    var failover: Bool { get { d.object(forKey: "mylo_failover") as? Bool ?? true } set { put("failover", newValue) } }
    var autoSelect: Bool { get { d.bool(forKey: "mylo_auto") } set { put("auto", newValue) } }
    var killSwitch: Bool { get { d.bool(forKey: "mylo_kill") } set { put("kill", newValue) } }
    var showIp: Bool { get { d.object(forKey: "mylo_showip") as? Bool ?? false } set { put("showip", newValue) } }
    var verify: Bool { get { d.object(forKey: "mylo_verify") as? Bool ?? true } set { put("verify", newValue) } }

    /// Unique local IKE id, generated once (LID in the router script).
    func localId() -> String {
        let v = str("lid")
        if !v.isEmpty { return v }
        var b = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        let id = "r" + b.map { String(format: "%02x", $0) }.joined()
        put("lid", id)
        return id
    }

    /// Fingerprint of the profile last sent to Settings (what was offered, not proof it was installed).
    var profileSent: String { get { str("profile_fp") } set { put("profile_fp", newValue) } }

    /// Id of the saved OpenVPN profile the power button connects to (empty = the IKEv2 locations).
    var activeOvpn: String { get { str("active_ovpn") } set { put("active_ovpn", newValue) } }

    /// The user confirmed that the "MYLO On" / "MYLO Off" shortcuts exist.
    var shortcutsReady: Bool { get { d.bool(forKey: "mylo_shortcuts") } set { put("shortcuts", newValue) } }

    /// Login-less builds: take the IKEv2 account from Defaults when none was entered yet.
    func seedAccountFromDefaults() {
        if user.isEmpty, !Defaults.vpnUser.isEmpty { user = Defaults.vpnUser }
        if pass.isEmpty, !Defaults.vpnPass.isEmpty { pass = Defaults.vpnPass }
    }

    /// One-time seeding of the built-in server list.
    func migrate() {
        if d.integer(forKey: "mylo_seed") >= 1 { return }
        let defaults = Defaults.servers()
        let extra = servers().filter { c in !defaults.contains { $0.address == c.address } }
            .map { s -> Server in var s = s; if s.cc.isEmpty { s.cc = guessCc(s.address) }; return s }
        saveServers(defaults + extra)
        if current.isEmpty || !(defaults + extra).contains(where: { $0.address == current }) {
            current = defaults.first?.address ?? ""
        }
        autoSelect = false
        put("seed", 1)
    }

    // MARK: favorites
    func favorites() -> Set<String> { Set(d.stringArray(forKey: "mylo_favs") ?? []) }
    func toggleFavorite(_ addr: String) -> Set<String> {
        var n = favorites()
        if !n.insert(addr).inserted { n.remove(addr) }
        put("favs", Array(n))
        return n
    }

    // MARK: day helpers
    private static func epochDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let u = utc.date(from: c) ?? date
        return Int(u.timeIntervalSince1970 / 86400)
    }
    private func dayKey(_ prefix: String, _ offset: Int) -> String {
        let dt = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return "mylo_\(prefix)_\(Store.epochDay(dt))"
    }

    // MARK: traffic usage + history
    func addBytes(rx: Int64, tx: Int64) {
        let kr = dayKey("rx", 0), kt = dayKey("tx", 0)
        d.set(Int64(d.double(forKey: kr)) + rx, forKey: kr)
        d.set(Int64(d.double(forKey: kt)) + tx, forKey: kt)
    }

    /// (rx, tx) summed over the last [days] days including today.
    func usage(days: Int) -> (rx: Int64, tx: Int64) {
        var rx: Int64 = 0, tx: Int64 = 0
        for i in 0..<days {
            rx += Int64(d.double(forKey: dayKey("rx", -i)))
            tx += Int64(d.double(forKey: dayKey("tx", -i)))
        }
        return (rx, tx)
    }

    func history() -> [Hist] {
        guard let data = d.data(forKey: "mylo_hist"), let h = try? JSONDecoder().decode([Hist].self, from: data) else { return [] }
        return h
    }

    func addHistory(_ h: Hist) {
        let all = Array(([h] + history()).prefix(60))
        if let data = try? JSONEncoder().encode(all) { put("hist", data) }
    }

    // MARK: servers
    func servers() -> [Server] {
        guard let data = d.data(forKey: "mylo_servers"), let s = try? JSONDecoder().decode([Server].self, from: data) else { return [] }
        return s
    }
    func saveServers(_ list: [Server]) {
        if let data = try? JSONEncoder().encode(list) { put("servers", data) }
    }

    // MARK: "Time Protected" card
    func addSeconds(_ n: Int) {
        let k = dayKey("u", 0)
        d.set(d.double(forKey: k) + Double(n), forKey: k)
    }

    /// Weekday index of today, Monday = 0.
    static func todayIndex() -> Int { (Calendar.current.component(.weekday, from: Date()) + 5) % 7 }

    /// Seconds protected for Mon..Sun of the current week.
    func week() -> [Int] {
        let monOffset = -Store.todayIndex()
        return (0..<7).map { i in Int(d.double(forKey: dayKey("u", monOffset + i))) }
    }

    // MARK: login lock-out (slows down guessing on this device)
    var failedLogins: Int { get { d.integer(forKey: "mylo_fails") } set { put("fails", newValue) } }
    var lockUntil: Double { get { d.double(forKey: "mylo_lockuntil") } set { put("lockuntil", newValue) } }
}

/// Same line format as the router's ikev2-servers.list:  name|address|cc|proto|file
enum ListParser {
    static func parse(_ text: String) -> [Server] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { return nil }
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let proto = f.count > 3 ? f[3].lowercased() : ""
            if !proto.isEmpty && proto != "ikev2" { return nil }   // OpenVPN/WG not supported here
            let addr = (f.count > 1 ? f[1] : f[0]).replacingOccurrences(of: " ", with: "")
            if addr.isEmpty { return nil }
            let name = (f.count > 1 && !f[0].isEmpty) ? f[0] : addr
            return Server(name: name, address: addr, cc: f.count > 2 ? f[2].uppercased() : guessCc(addr))
        }
    }
}
