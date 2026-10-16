#if !APPSTORE   // free-Apple-ID build only: App Store builds never install profiles
import Foundation
import Network
import UIKit
import CryptoKit

/// Builds a .mobileconfig with an IKEv2 VPN payload. Installing it needs no entitlement, so it works with a
/// free Apple ID; the VPN is then switched on from iOS Settings > VPN. The same identifier is always used, so
/// installing a new profile for another location replaces the previous one.
enum ProfileExport {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Changes whenever the installed profile would have to change (locations, account, ids).
    static func fingerprint(_ servers: [Server], store: Store = .shared) -> String {
        let key = servers.map { $0.address }.sorted().joined(separator: ",")
            + "|" + store.user + "|" + store.pass + "|" + store.remoteId + "|" + store.issuerCN + "|" + store.localId()
        return SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func payload(for s: Server, store: Store) -> String {
        let rid = store.remoteId.isEmpty ? Defaults.rid : store.remoteId
        let issuer = store.issuerCN.isEmpty ? "" : "\n                <key>ServerCertificateIssuerCommonName</key><string>\(esc(store.issuerCN))</string>"
        let label = "MYLO VPN"   // fixed: the Shortcuts "Set VPN" action finds the entry by this name
        return """
            <dict>
              <key>PayloadType</key><string>com.apple.vpn.managed</string>
              <key>PayloadVersion</key><integer>1</integer>
              <key>PayloadIdentifier</key><string>com.mylo.vpn.config</string>
              <key>PayloadUUID</key><string>6F1E1A2C-5B7D-4E55-9A63-3C0B7D2A4F10</string>
              <key>PayloadDisplayName</key><string>\(esc(label))</string>
              <key>UserDefinedName</key><string>\(esc(label))</string>
              <key>VPNType</key><string>IKEv2</string>
              <key>IKEv2</key>
              <dict>
                <key>RemoteAddress</key><string>\(esc(s.address))</string>
                <key>RemoteIdentifier</key><string>\(esc(rid))</string>
                <key>LocalIdentifier</key><string>\(esc(store.localId()))</string>
                <key>AuthenticationMethod</key><string>None</string>
                <key>ExtendedAuthEnabled</key><integer>1</integer>
                <key>AuthName</key><string>\(esc(store.user))</string>
                <key>AuthPassword</key><string>\(esc(store.pass))</string>\(issuer)
                <key>DeadPeerDetectionRate</key><string>Medium</string>
                <key>OnDemandEnabled</key><integer>0</integer>
                <key>IKESecurityAssociationParameters</key>
                <dict>
                  <key>EncryptionAlgorithm</key><string>AES-256</string>
                  <key>IntegrityAlgorithm</key><string>SHA2-256</string>
                  <key>DiffieHellmanGroup</key><integer>14</integer>
                  <key>LifeTimeInMinutes</key><integer>1440</integer>
                </dict>
                <key>ChildSecurityAssociationParameters</key>
                <dict>
                  <key>EncryptionAlgorithm</key><string>AES-256</string>
                  <key>IntegrityAlgorithm</key><string>SHA2-256</string>
                  <key>DiffieHellmanGroup</key><integer>14</integer>
                  <key>LifeTimeInMinutes</key><integer>1440</integer>
                </dict>
              </dict>
            </dict>
        """
    }

    /// Exactly one VPN entry, "MYLO VPN". Installing for another location replaces that same entry (same
    /// identifier and UUID), so Settings > VPN never shows more than one.
    static func xml(for server: Server, store: Store = .shared) -> String {
        let items = payload(for: server, store: store)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>PayloadContent</key>
          <array>
        \(items)
          </array>
          <key>PayloadDisplayName</key><string>MYLO VPN</string>
          <key>PayloadIdentifier</key><string>com.mylo.vpn.profile</string>
          <key>PayloadType</key><string>Configuration</string>
          <key>PayloadUUID</key><string>A3C5D7E9-1B2D-4F60-8E71-9D0C2B4A6E80</string>
          <key>PayloadVersion</key><integer>1</integer>
        </dict>
        </plist>
        """
    }
}

/// Serves the profile from 127.0.0.1 so Safari can download it and offer the install prompt.
/// The listener is bound to the loopback address only (never reachable from the Wi-Fi/cellular network), and the
/// file is served only on a random, unguessable path, so other apps on the phone cannot fetch it by scanning ports.
final class ProfileServer: @unchecked Sendable {
    private var listener: NWListener?
    private var payload = Data()
    private let token = UUID().uuidString

    func start(serving data: Data) async -> URL? {
        payload = data
        return await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            let once = OnceBox<URL?> { c.resume(returning: $0) }
            do {
                let params = NWParameters.tcp
                params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)   // 127.0.0.1 only
                let l = try NWListener(using: params)
                let token = self.token
                l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
                l.stateUpdateHandler = { st in
                    switch st {
                    case .ready:
                        if let p = l.port { once.fire(URL(string: "http://127.0.0.1:\(p.rawValue)/\(token)/MYLO-VPN.mobileconfig")) } else { once.fire(nil) }
                    case .failed: once.fire(nil)
                    default: break
                    }
                }
                l.start(queue: .global())
                listener = l
            } catch { once.fire(nil) }
        }
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: .global())
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { c.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            guard request.hasPrefix("GET /\(self.token)/") else {
                let nf = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                c.send(content: Data(nf.utf8), completion: .contentProcessed { _ in c.cancel() })
                return
            }
            var head = "HTTP/1.1 200 OK\r\n"
            head += "Content-Type: application/x-apple-aspen-config\r\n"
            head += "Content-Length: \(self.payload.count)\r\n"
            head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            var out = Data(head.utf8)
            out.append(self.payload)
            c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    func stop() { listener?.cancel(); listener = nil }
}

private final class BgTask {
    var id = UIBackgroundTaskIdentifier.invalid
    func begin() { id = UIApplication.shared.beginBackgroundTask(withName: "profile") { [weak self] in self?.end() } }
    func end() { if id != .invalid { UIApplication.shared.endBackgroundTask(id); id = .invalid } }
}

@MainActor
enum ProfileInstaller {
    private static var current: ProfileServer?

    /// Starts the local server and opens Safari, which then offers to install the profile.
    static func install(server: Server) async -> Bool {
        guard let data = ProfileExport.xml(for: server).data(using: .utf8) else { return false }
        current?.stop()
        let srv = ProfileServer()
        guard let url = await srv.start(serving: data) else { return false }
        current = srv
        let bg = BgTask()
        bg.begin()
        let opened = await UIApplication.shared.open(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { srv.stop(); bg.end() }
        return opened
    }
}
#endif
