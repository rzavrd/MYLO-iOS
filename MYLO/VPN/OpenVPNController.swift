#if OPENVPN
import Foundation
import NetworkExtension

/// App side of OpenVPN: configures a `NETunnelProviderManager` that starts the MYLOTunnel extension.
/// Needs the Network Extension (packet-tunnel-provider) entitlement, i.e. a paid developer account.
@MainActor
final class OpenVPNController {
    static let shared = OpenVPNController()
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var currentName = "OpenVPN"
    private var lastStatus: NEVPNStatus = .invalid

    /// The extension's bundle id must be "<app bundle id>.tunnel" (see project.yml).
    private var tunnelId: String { (Bundle.main.bundleIdentifier ?? "com.mylo.vpn") + ".tunnel" }

    private func find() async throws -> NETunnelProviderManager {
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        return all.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelId }
            ?? NETunnelProviderManager()
    }

    func connect(_ c: ImportedConfig, raw: String, auth: (user: String, pass: String)?) async throws {
        let m = try await find()
        let p = NETunnelProviderProtocol()
        p.providerBundleIdentifier = tunnelId
        p.serverAddress = c.host
        var cfg: [String: Any] = ["ovpn": Data(raw.utf8)]
        if let a = auth { cfg["user"] = a.user; cfg["pass"] = a.pass }
        p.providerConfiguration = cfg
        m.protocolConfiguration = p
        m.localizedDescription = "MYLO OpenVPN"
        m.isEnabled = true
        try await m.saveToPreferences()
        try await m.loadFromPreferences()      // required before starting after a save
        currentName = c.name
        attach(m)
        try m.connection.startVPNTunnel()
    }

    func disconnect() { manager?.connection.stopVPNTunnel() }

    /// App relaunched while the tunnel is still running: pick it up again.
    func restore() async {
        guard let m = try? await find(), m.protocolConfiguration != nil else { return }
        let s = m.connection.status
        guard s == .connected || s == .connecting || s == .reasserting else { return }
        currentName = m.localizedDescription ?? "OpenVPN"
        attach(m)
    }

    private func attach(_ m: NETunnelProviderManager) {
        manager = m
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: m.connection, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.changed() }
        }
        changed(force: true)
    }

    private func changed(force: Bool = false) {
        guard let m = manager else { return }
        let s = m.connection.status
        guard force || s != lastStatus else { return }
        lastStatus = s
        if s == .disconnected || s == .invalid {
            m.connection.fetchLastDisconnectError { [weak self] err in
                Task { @MainActor in
                    guard let self else { return }
                    VpnController.shared.openVPNStatus(s, name: self.currentName, since: nil,
                                                       error: (err as NSError?)?.localizedDescription)
                }
            }
        } else {
            VpnController.shared.openVPNStatus(s, name: currentName, since: m.connection.connectedDate, error: nil)
        }
    }
}
#endif
