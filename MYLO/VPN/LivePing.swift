import Foundation

/// Live latency of the real (non-VPN) connection to Iranian sites, and of the tunnel.
/// iOS routes everything through the tunnel while connected, so the direct probe only makes sense when the VPN is off.
enum LivePing {
    private static let domestic = ["www.digikala.com", "www.aparat.com"]

    static func direct() async -> Int? {
        for h in domestic {
            if let ms = await Probe.tcpLatency(host: h, port: 443) { return ms }
        }
        return nil
    }

    /// Round trip through the default route (= the tunnel while connected).
    static func vpn() async -> Int? { await Probe.tcpLatency(host: "1.1.1.1", port: 443) }
}
