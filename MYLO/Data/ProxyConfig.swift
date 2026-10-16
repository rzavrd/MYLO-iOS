import Foundation
import Security

enum ConfigKind: String, Codable, CaseIterable {
    case vless, vmess, trojan, openvpn
    var title: String {
        switch self {
        case .vless: return "VLESS"
        case .vmess: return "VMess"
        case .trojan: return "Trojan"
        case .openvpn: return "OpenVPN"
        }
    }
}

/// What the list shows. The secret part (link / .ovpn text) lives in the Keychain, keyed by `id`.
struct ImportedConfig: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: ConfigKind
    var host: String
    var port: Int
    var added: Double
}

struct ParsedConfig {
    var kind: ConfigKind
    var name: String
    var host: String
    var port: Int
    var raw: String                   // original link, or the full .ovpn text
    var outbound: [String: Any]?      // sing-box outbound (nil for OpenVPN)
}

enum ConfigParseError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(m) = self { return m }; return nil }
}

enum ConfigParser {
    // MARK: entry points

    /// Accepts one or many links (one per line), a base64 subscription, or the text of an .ovpn file.
    static func parseAll(_ input: String, filename: String? = nil) -> (ok: [ParsedConfig], errors: [String]) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return ([], ["Nothing to import."]) }
        if looksLikeOvpn(text) {
            do { return ([try parseOvpn(text, filename: filename)], []) }
            catch { return ([], [error.localizedDescription]) }
        }
        var lines = splitLines(text)
        if !lines.contains(where: hasKnownScheme), let d = b64(text), let dec = String(data: d, encoding: .utf8) {
            lines = splitLines(dec)          // subscription = base64 of a list of links
        }
        var ok: [ParsedConfig] = [], errors: [String] = []
        for l in lines {
            guard hasKnownScheme(l) else { errors.append("Not a supported link: \(l.prefix(40))"); continue }
            do { ok.append(try parseLink(l)) } catch { errors.append(error.localizedDescription) }
        }
        return (ok, errors)
    }

    static func parseLink(_ link: String) throws -> ParsedConfig {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if l.lowercased().hasPrefix("vmess://") { return try parseVmess(l) }
        if l.lowercased().hasPrefix("vless://") { return try parseUrlStyle(l, kind: .vless) }
        if l.lowercased().hasPrefix("trojan://") { return try parseUrlStyle(l, kind: .trojan) }
        throw ConfigParseError.invalid("Unsupported link.")
    }

    /// true when the profile asks for a username/password (`auth-user-pass` without a credentials file).
    static func needsAuth(_ ovpn: String) -> Bool {
        for raw in ovpn.split(whereSeparator: \.isNewline) {
            let f = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if f.first == "auth-user-pass" && f.count == 1 { return true }
        }
        return false
    }

    // MARK: helpers

    private static func splitLines(_ t: String) -> [String] {
        t.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func hasKnownScheme(_ l: String) -> Bool {
        let x = l.lowercased()
        return x.hasPrefix("vless://") || x.hasPrefix("vmess://") || x.hasPrefix("trojan://")
    }

    static func b64(_ s: String) -> Data? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    private static func looksLikeOvpn(_ t: String) -> Bool {
        if hasKnownScheme(t) { return false }
        let l = t.lowercased()
        return l.contains("\nremote ") || l.hasPrefix("remote ") || l.contains("<ca>") || (l.contains("client") && l.contains("dev "))
    }

    private static func check(host: String, port: Int) throws {
        guard !host.isEmpty else { throw ConfigParseError.invalid("Missing server address.") }
        guard (1...65535).contains(port) else { throw ConfigParseError.invalid("Invalid port \(port).") }
    }

    // MARK: sing-box building blocks

    private static func tlsBlock(_ q: [String: String], host: String, defaultOn: Bool = false) -> [String: Any]? {
        let sec = (q["security"] ?? q["tls"] ?? (defaultOn ? "tls" : "")).lowercased()
        guard sec == "tls" || sec == "reality" || sec == "true" || sec == "1" else { return nil }
        var t: [String: Any] = ["enabled": true, "server_name": q["sni"] ?? q["peer"] ?? q["host"] ?? host]
        if let a = q["alpn"], !a.isEmpty { t["alpn"] = a.split(separator: ",").map { String($0) } }
        if q["allowInsecure"] == "1" || q["insecure"] == "1" { t["insecure"] = true }
        let fp = q["fp"] ?? ""
        if sec == "reality" {
            t["utls"] = ["enabled": true, "fingerprint": fp.isEmpty ? "chrome" : fp]
            t["reality"] = ["enabled": true, "public_key": q["pbk"] ?? "", "short_id": q["sid"] ?? ""]
        } else if !fp.isEmpty {
            t["utls"] = ["enabled": true, "fingerprint": fp]
        }
        return t
    }

    private static func transportBlock(_ q: [String: String]) -> [String: Any]? {
        let type = (q["type"] ?? q["net"] ?? "tcp").lowercased()
        let host = q["host"] ?? ""
        let path = q["path"] ?? ""
        switch type {
        case "ws":
            var t: [String: Any] = ["type": "ws"]
            if !path.isEmpty { t["path"] = path }
            if !host.isEmpty { t["headers"] = ["Host": host] }
            return t
        case "grpc":
            return ["type": "grpc", "service_name": q["serviceName"] ?? path]
        case "http", "h2":
            var t: [String: Any] = ["type": "http"]
            if !host.isEmpty { t["host"] = host.split(separator: ",").map { String($0) } }
            if !path.isEmpty { t["path"] = path }
            return t
        case "httpupgrade":
            var t: [String: Any] = ["type": "httpupgrade"]
            if !host.isEmpty { t["host"] = host }
            if !path.isEmpty { t["path"] = path }
            return t
        default:
            return nil      // plain tcp
        }
    }

    // MARK: vless:// and trojan://

    private static func parseUrlStyle(_ link: String, kind: ConfigKind) throws -> ParsedConfig {
        let parts = link.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
        guard let c = URLComponents(string: String(parts[0])), let host = c.host, !host.isEmpty else {
            throw ConfigParseError.invalid("\(kind.title) link is malformed.")
        }
        let port = c.port ?? (kind == .trojan ? 443 : 0)
        try check(host: host, port: port)
        guard let secret = c.user, !secret.isEmpty else {
            throw ConfigParseError.invalid("\(kind.title) link has no \(kind == .vless ? "UUID" : "password").")
        }
        var q: [String: String] = [:]
        for i in c.queryItems ?? [] { if let v = i.value { q[i.name] = v } }

        var o: [String: Any] = ["type": kind.rawValue, "tag": "proxy", "server": host, "server_port": port]
        if kind == .vless {
            o["uuid"] = secret
            if let f = q["flow"], !f.isEmpty { o["flow"] = f }
            o["packet_encoding"] = "xudp"
        } else {
            o["password"] = secret.removingPercentEncoding ?? secret
        }
        if let t = tlsBlock(q, host: host, defaultOn: kind == .trojan) { o["tls"] = t }
        if let t = transportBlock(q) { o["transport"] = t }
        return ParsedConfig(kind: kind, name: name.isEmpty ? "\(host):\(port)" : name, host: host, port: port,
                            raw: link, outbound: o)
    }

    // MARK: vmess://

    private static func parseVmess(_ link: String) throws -> ParsedConfig {
        let body = String(link.dropFirst("vmess://".count))
        guard let d = b64(body), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw ConfigParseError.invalid("VMess link is not valid base64 JSON.")
        }
        func s(_ k: String) -> String { if let v = obj[k] as? String { return v }; if let n = obj[k] as? NSNumber { return n.stringValue }; return "" }
        let host = s("add"), port = Int(s("port")) ?? 0
        try check(host: host, port: port)
        guard !s("id").isEmpty else { throw ConfigParseError.invalid("VMess link has no UUID.") }
        let q: [String: String] = ["net": s("net"), "host": s("host"), "path": s("path"), "tls": s("tls"),
                                   "sni": s("sni"), "alpn": s("alpn"), "fp": s("fp")]
        var o: [String: Any] = ["type": "vmess", "tag": "proxy", "server": host, "server_port": port,
                                "uuid": s("id"), "security": s("scy").isEmpty ? "auto" : s("scy"),
                                "alter_id": Int(s("aid")) ?? 0]
        if let t = tlsBlock(q, host: host) { o["tls"] = t }
        if let t = transportBlock(q) { o["transport"] = t }
        let name = s("ps")
        return ParsedConfig(kind: .vmess, name: name.isEmpty ? "\(host):\(port)" : name, host: host, port: port,
                            raw: link, outbound: o)
    }

    // MARK: .ovpn

    static func parseOvpn(_ text: String, filename: String?) throws -> ParsedConfig {
        var host = "", port = 1194
        for raw in text.split(whereSeparator: \.isNewline) {
            let f = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if f.first == "remote", f.count >= 2 {
                host = f[1]
                if f.count >= 3, let p = Int(f[2]) { port = p }
                break
            }
        }
        guard !host.isEmpty else { throw ConfigParseError.invalid("This .ovpn file has no \"remote\" line.") }
        try check(host: host, port: port)
        var name = (filename ?? "").replacingOccurrences(of: ".ovpn", with: "", options: [.caseInsensitive])
        if name.isEmpty { name = host }
        return ParsedConfig(kind: .openvpn, name: name, host: host, port: port, raw: text, outbound: nil)
    }
}

/// Persistence: list in UserDefaults, secrets (links, .ovpn text with keys) in the Keychain.
enum ConfigStore {
    private static let key = "mylo_configs"

    static func list() -> [ImportedConfig] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let l = try? JSONDecoder().decode([ImportedConfig].self, from: d) else { return [] }
        return l
    }

    private static func save(_ l: [ImportedConfig]) {
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// Returns false when the same config is already stored.
    @discardableResult
    static func add(_ p: ParsedConfig) -> Bool {
        var all = list()
        if all.contains(where: { Keychain.get("cfg-" + $0.id) == p.raw }) { return false }
        let id = UUID().uuidString
        Keychain.set("cfg-" + id, p.raw)
        all.insert(ImportedConfig(id: id, name: p.name, kind: p.kind, host: p.host, port: p.port,
                                  added: Date().timeIntervalSince1970), at: 0)
        save(all)
        return true
    }

    static func remove(_ id: String) {
        Keychain.delete("cfg-" + id)
        Keychain.delete("cfgauth-" + id)
        if Store.shared.activeOvpn == id { Store.shared.activeOvpn = "" }
        save(list().filter { $0.id != id })
    }

    static func raw(_ id: String) -> String? { Keychain.get("cfg-" + id) }

    /// id of the stored config with exactly this text.
    static func id(forRaw text: String) -> String? { list().first { Keychain.get("cfg-" + $0.id) == text }?.id }

    /// Reuses the username/password already saved for another OpenVPN profile (a provider such as PureVPN uses one
    /// account for all of its files), so a newly opened .ovpn can connect without asking again.
    static func inheritAuth(for id: String) -> (user: String, pass: String)? {
        for c in list() where c.id != id && c.kind == .openvpn {
            if let a = auth(c.id) { setAuth(id, user: a.user, pass: a.pass); return a }
        }
        return nil
    }

    /// Username/password for .ovpn profiles that use `auth-user-pass` (Keychain, per profile).
    static func auth(_ id: String) -> (user: String, pass: String)? {
        guard let s = Keychain.get("cfgauth-" + id), let i = s.firstIndex(of: "\n") else { return nil }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }
    static func setAuth(_ id: String, user: String, pass: String) {
        if user.isEmpty && pass.isEmpty { Keychain.delete("cfgauth-" + id) } else { Keychain.set("cfgauth-" + id, user + "\n" + pass) }
    }

    /// Complete sing-box configuration for a stored VLESS/VMess/Trojan entry. This is what the Packet Tunnel
    /// extension (see README) hands to the core; nothing in the app runs it yet.
    static func singBoxJSON(for id: String) -> String? {
        guard let raw = raw(id), let o = ConfigParser.parseAll(raw).ok.first?.outbound else { return nil }
        let cfg: [String: Any] = [
            "log": ["level": "warn"],
            "inbounds": [["type": "tun", "address": ["172.19.0.1/30"], "auto_route": true, "stack": "system"]],
            "outbounds": [o, ["type": "direct", "tag": "direct"]],
            "route": ["final": "proxy", "auto_detect_interface": true],
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
