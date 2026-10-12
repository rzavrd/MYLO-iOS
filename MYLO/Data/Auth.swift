import Foundation
import CryptoKit
import CommonCrypto

// MARK: - users.json (made by tools/mylo_users.py)

struct UsersFile: Decodable {
    struct Entry: Decodable { let s: String; let n: String; let c: String }   // salt, nonce, ciphertext||tag (base64)
    let v: Int
    let iter: Int
    let users: [String: Entry]
}

/// What an opened entry contains.
struct Payload: Decodable {
    let name: String?
    let vpnUser: String
    let vpnPass: String
    let rid: String?
    let exp: Double?
}

struct Session: Codable {
    var id: String          // sha256("mylo:" + login)
    var login: String
    var name: String
    var vpnUser: String
    var vpnPass: String
    var rid: String
    var exp: Double?        // unix seconds, nil = never
    var verified: Double    // last time users.json confirmed this account
    var key: String         // base64 AES key derived from the password (the password itself is not kept)
}

enum AuthError: Error {
    case invalid, expired, notConfigured
    case network(String)
}

enum AuthCrypto {
    static func userId(_ login: String) -> String {
        let h = SHA256.hash(data: Data(("mylo:" + login.trimmingCharacters(in: .whitespaces).lowercased()).utf8))
        return h.map { String(format: "%02x", $0) }.joined()
    }

    /// PBKDF2-HMAC-SHA256, 32 bytes.
    static func deriveKey(password: String, salt: Data, iter: Int) -> Data? {
        guard !password.isEmpty, iter > 0 else { return nil }
        let pw = Array(password.utf8)
        let saltBytes = [UInt8](salt)
        var out = [UInt8](repeating: 0, count: 32)
        let rc = pw.withUnsafeBufferPointer { pwp in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                 UnsafeRawPointer(pwp.baseAddress!).assumingMemoryBound(to: Int8.self), pw.count,
                                 saltBytes, saltBytes.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iter),
                                 &out, out.count)
        }
        return rc == Int32(kCCSuccess) ? Data(out) : nil
    }

    /// AES-256-GCM open. nil = wrong key (wrong password) or tampered file.
    static func open(_ e: UsersFile.Entry, id: String, key: Data) -> Payload? {
        guard let nonceData = Data(base64Encoded: e.n), let blob = Data(base64Encoded: e.c), blob.count > 16,
              let nonce = try? AES.GCM.Nonce(data: nonceData) else { return nil }
        let ct = blob.prefix(blob.count - 16)
        let tag = blob.suffix(16)
        guard let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(id.utf8)) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: plain)
    }
}

enum AuthService {
    /// Remote users.json first; the copy pasted into Defaults.embeddedUsers is the fallback.
    static func loadUsers() async throws -> UsersFile {
        var lastError: String?
        if let u = URL(string: Defaults.authURL), u.scheme == "https" {
            do {
                let req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                return try JSONDecoder().decode(UsersFile.self, from: data)
            } catch {
                lastError = error.localizedDescription
            }
        }
        let emb = Defaults.embeddedUsers.trimmingCharacters(in: .whitespacesAndNewlines)
        if !emb.isEmpty, let f = try? JSONDecoder().decode(UsersFile.self, from: Data(emb.utf8)) { return f }
        if Defaults.authURL.isEmpty { throw AuthError.notConfigured }
        throw AuthError.network(lastError ?? "no connection")
    }
}

// MARK: - login state

@MainActor
final class AuthModel: ObservableObject {
    @Published private(set) var session: Session?
    @Published var busy = false
    @Published var error: String?

    private let store = Store.shared
    private static let maxOfflineDays = 7.0

    init() {
        if let json = Keychain.get("session"), let s = try? JSONDecoder().decode(Session.self, from: Data(json.utf8)) {
            session = s
            apply(s)
        }
    }

    var isLoggedIn: Bool { session != nil }

    private func save(_ s: Session) {
        if let d = try? JSONEncoder().encode(s), let j = String(data: d, encoding: .utf8) { Keychain.set("session", j) }
    }

    /// Hands the VPN account from the session to the connection code.
    private func apply(_ s: Session) {
        store.user = s.vpnUser
        store.pass = s.vpnPass
        store.remoteId = s.rid
    }

    func login(_ loginRaw: String, _ password: String) async {
        let login = loginRaw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !login.isEmpty, !password.isEmpty else { error = "Enter your username and password."; return }
        let wait = store.lockUntil - Date().timeIntervalSince1970
        if wait > 0 { error = "Too many attempts. Try again in \(Int(wait.rounded(.up))) s."; return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let file = try await AuthService.loadUsers()
            let id = AuthCrypto.userId(login)
            guard let entry = file.users[id], let salt = Data(base64Encoded: entry.s) else { throw AuthError.invalid }
            let iter = file.iter
            let key = await Task.detached(priority: .userInitiated) {
                AuthCrypto.deriveKey(password: password, salt: salt, iter: iter)
            }.value
            guard let key = key, let p = AuthCrypto.open(entry, id: id, key: key) else { throw AuthError.invalid }
            if let exp = p.exp, Date().timeIntervalSince1970 > exp { throw AuthError.expired }
            let s = Session(id: id, login: login, name: p.name ?? login, vpnUser: p.vpnUser, vpnPass: p.vpnPass,
                            rid: p.rid ?? Defaults.rid, exp: p.exp, verified: Date().timeIntervalSince1970,
                            key: key.base64EncodedString())
            store.failedLogins = 0
            store.lockUntil = 0
            save(s)
            apply(s)
            session = s
        } catch AuthError.expired {
            self.error = "This account has expired."
        } catch AuthError.notConfigured {
            self.error = "Login server is not set up yet (Defaults.authURL / embeddedUsers)."
        } catch AuthError.network(let m) {
            self.error = "Cannot reach the login server (\(m)). Check your internet."
        } catch {
            store.failedLogins += 1
            let n = store.failedLogins
            if n >= 5 { store.lockUntil = Date().timeIntervalSince1970 + min(Double(1 << min(n - 4, 8)) * 5, 300) }
            self.error = "Wrong username or password."
        }
    }

    func logout(reason: String? = nil) {
        Keychain.delete("session")
        store.user = ""
        store.pass = ""
        session = nil
        error = reason
    }

    /// Silent re-check: removed or expired users are locked out, everybody else gets fresh VPN details.
    func refresh() async {
        guard var s = session else { return }
        if let exp = s.exp, Date().timeIntervalSince1970 > exp { logout(reason: "This account has expired."); return }
        do {
            let file = try await AuthService.loadUsers()
            guard let entry = file.users[s.id], let key = Data(base64Encoded: s.key),
                  let p = AuthCrypto.open(entry, id: s.id, key: key) else {
                logout(reason: "Your access was removed or your password was changed. Please sign in again.")
                return
            }
            if let exp = p.exp, Date().timeIntervalSince1970 > exp { logout(reason: "This account has expired."); return }
            s.vpnUser = p.vpnUser; s.vpnPass = p.vpnPass; s.rid = p.rid ?? s.rid
            s.name = p.name ?? s.name; s.exp = p.exp
            s.verified = Date().timeIntervalSince1970
            save(s); apply(s); session = s
        } catch AuthError.notConfigured {
            // nothing to check against
        } catch {
            let days = (Date().timeIntervalSince1970 - s.verified) / 86400
            if days > Self.maxOfflineDays { logout(reason: "Connect to the internet to verify your account.") }
        }
    }
}
