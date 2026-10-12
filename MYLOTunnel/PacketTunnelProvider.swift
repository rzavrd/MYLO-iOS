import NetworkExtension
import OpenVPNAdapter

// OpenVPNAdapter wraps the OpenVPN 3 core (AGPL-3.0). See docs/OPENVPN.md for what that means for licensing.
extension NEPacketTunnelFlow: OpenVPNAdapterPacketFlow {}

/// Runs inside the Network Extension process: receives the .ovpn text (and optional username/password) from the
/// app through `providerConfiguration` and hands them to the OpenVPN core.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var adapter: OpenVPNAdapter = {
        let a = OpenVPNAdapter()
        a.delegate = self
        return a
    }()

    private var startHandler: ((Error?) -> Void)?
    private var stopHandler: (() -> Void)?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let cfg = proto.providerConfiguration,
              let ovpn = cfg["ovpn"] as? Data else {
            completionHandler(NSError(domain: "MYLOTunnel", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "No OpenVPN configuration was passed to the tunnel."]))
            return
        }

        let conf = OpenVPNConfiguration()
        conf.fileContent = ovpn
        conf.tunPersist = true

        let props: OpenVPNProperties
        do { props = try adapter.apply(configuration: conf) } catch { completionHandler(error); return }

        if !props.autologinEnabled {
            let user = cfg["user"] as? String ?? ""
            let pass = cfg["pass"] as? String ?? ""
            let creds = OpenVPNCredentials()
            creds.username = user
            creds.password = pass
            do { try adapter.provide(credentials: creds) } catch { completionHandler(error); return }
        }

        startHandler = completionHandler
        adapter.connect(using: packetFlow)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopHandler = completionHandler
        adapter.disconnect()
    }
}

extension PacketTunnelProvider: OpenVPNAdapterDelegate {
    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter,
                        configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?,
                        completionHandler: @escaping (Error?) -> Void) {
        setTunnelNetworkSettings(networkSettings, completionHandler: completionHandler)
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleEvent event: OpenVPNAdapterEvent, message: String?) {
        switch event {
        case .connected:
            if reasserting { reasserting = false }
            startHandler?(nil); startHandler = nil
        case .disconnected:
            stopHandler?(); stopHandler = nil
        case .reconnecting:
            reasserting = true
        default:
            break
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error) {
        let fatal = (error as NSError).userInfo[OpenVPNAdapterErrorFatalKey] as? Bool ?? false
        guard fatal else { return }
        if let h = startHandler { h(error); startHandler = nil } else { cancelTunnelWithError(error) }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleLogMessage logMessage: String) {
        NSLog("[MYLOTunnel] %@", logMessage)
    }
}
