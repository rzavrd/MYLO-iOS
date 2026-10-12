import Foundation
import Darwin
import Network

/// Observes the VPN tunnel interface.
///
/// IMPORTANT: the mere existence of a `utunN` / `ipsecN` / `pppN` interface, even one with an IPv4 address, proves
/// nothing. iOS creates `utun` interfaces for its own services while no VPN is running. The only thing that is
/// accepted as evidence here is `vpn()`: the interface that owns the source address iOS picks for ordinary
/// internet traffic, and only when that interface is a tunnel. If the default route still goes out through
/// Wi-Fi / cellular (`en0`, `pdp_ip0`) there is no active VPN, whatever utun interfaces exist.
enum NetIf {
    struct Snapshot { var rx: UInt32 = 0; var tx: UInt32 = 0; var ip: String?; var name: String? }

    static func isTunnelName(_ name: String) -> Bool {
        name.hasPrefix("ipsec") || name.hasPrefix("utun") || name.hasPrefix("ppp")
    }

    /// Every IPv4 address on the device as (interface name, address in network byte order).
    private static func ipv4Addresses() -> [(name: String, addr: UInt32)] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return [] }
        defer { freeifaddrs(ifap) }
        var out: [(name: String, addr: UInt32)] = []
        var p = ifap
        while let a = p {
            defer { p = a.pointee.ifa_next }
            guard let sa = a.pointee.ifa_addr, Int32(sa.pointee.sa_family) == AF_INET else { continue }
            let v4 = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            out.append((name: String(cString: a.pointee.ifa_name), addr: v4))
        }
        return out
    }

    /// Byte counters + IPv4 text of one named interface.
    static func snapshot(named name: String) -> Snapshot? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return nil }
        defer { freeifaddrs(ifap) }
        var s = Snapshot(); s.name = name
        var seen = false
        var p = ifap
        while let a = p {
            defer { p = a.pointee.ifa_next }
            guard String(cString: a.pointee.ifa_name) == name, let sa = a.pointee.ifa_addr else { continue }
            seen = true
            switch Int32(sa.pointee.sa_family) {
            case AF_LINK:
                if let data = a.pointee.ifa_data {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    s.rx = d.ifi_ibytes; s.tx = d.ifi_obytes
                }
            case AF_INET:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    s.ip = String(cString: host)
                }
            default: break
            }
        }
        return seen ? s : nil
    }

    /// Name of the interface iOS would use for traffic to the internet (nothing is sent: UDP connect() only
    /// selects a route and a source address).
    static func defaultRouteInterface() -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        for target in ["1.1.1.1", "8.8.8.8"] {
            var dst = sockaddr_in()
            dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dst.sin_family = sa_family_t(AF_INET)
            dst.sin_port = UInt16(53).bigEndian
            guard inet_pton(AF_INET, target, &dst.sin_addr) == 1 else { continue }
            let rc = withUnsafePointer(to: &dst) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard rc == 0 else { continue }
            var local = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let ok = withUnsafeMutablePointer(to: &local) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
            }
            guard ok == 0 else { continue }
            if let hit = ipv4Addresses().first(where: { $0.addr == local.sin_addr.s_addr }) { return hit.name }
        }
        return nil
    }

    /// The tunnel that currently carries the default IPv4 route, or an empty snapshot if there is none.
    /// This is the ONLY routing-based evidence of an active VPN used by the app.
    static func vpn() -> Snapshot {
        guard let name = defaultRouteInterface(), isTunnelName(name), let s = snapshot(named: name), s.ip != nil else {
            return Snapshot()
        }
        return s
    }

    /// Diagnostics only (never used to decide the connection state): tunnel-looking interfaces that have IPv4.
    static func tunnelsForDiagnostics() -> [String] {
        Array(Set(ipv4Addresses().map { $0.name }.filter(isTunnelName))).sorted()
    }
}

/// Resumes a continuation at most once, from any thread.
final class OnceBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let body: (T) -> Void
    init(_ body: @escaping (T) -> Void) { self.body = body }
    func fire(_ v: T) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body(v) }
    }
}

enum Probe {
    /// IPv4 address of a host name (numeric strings come back unchanged), nil if DNS fails.
    static func resolveIPv4(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let ai = res, let sa = ai.pointee.ai_addr else { return nil }
        defer { freeaddrinfo(res) }
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(sa, ai.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: buf)
    }

    /// Time to open a TCP connection to host:port in ms (DNS time excluded), nil on failure / 3 s timeout.
    static func tcpLatency(host: String, port: UInt16) async -> Int? {
        await withCheckedContinuation { (c: CheckedContinuation<Int?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                guard let ip = resolveIPv4(host) else { c.resume(returning: nil); return }
                let conn = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
                let t0 = DispatchTime.now().uptimeNanoseconds
                let once = OnceBox<Int?> { v in conn.cancel(); c.resume(returning: v) }
                conn.stateUpdateHandler = { st in
                    switch st {
                    case .ready: once.fire(Int((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
                    case .failed, .cancelled: once.fire(nil)
                    default: break
                    }
                }
                conn.start(queue: .global())
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.fire(nil) }
            }
        }
    }
}
