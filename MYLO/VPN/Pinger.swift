import Foundation
import Darwin

/// Port of Pinger.kt. Probe = an IKE_SA_INIT request on UDP/500: any answer from the gateway (accept or error)
/// gives the round trip. ICMP echo is the fallback. Results are reported one by one through `progress`.
enum Pinger {
    struct PingResult { var ms: Int?; var how: String }   // how: ike / icmp / dns / none

    static func ping(_ host: String) async -> PingResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: probe(host)) }
        }
    }

    static func icmpSocketStatus() -> String {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        if fd < 0 { return "icmp socket error \(errno): \(String(cString: strerror(errno)))" }
        close(fd)
        return "icmp socket ok"
    }

    /// `progress` is called after every server; `note` receives diagnostic lines (self-test + summary).
    static func pingAll(_ list: [Server],
                        progress: (@MainActor (String, Int?) -> Void)? = nil,
                        note: (@MainActor (String) -> Void)? = nil) async -> [Server] {
        if let note {
            let t = await ping("1.1.1.1")
            let r = t.ms.map { "\($0) ms via \(t.how)" } ?? "no reply (\(t.how))"
            await note("ping self-test 1.1.1.1: \(r); \(icmpSocketStatus())")
        }
        var tally = ["icmp": 0, "ike": 0, "dns": 0, "none": 0]
        let out: [Server] = await withTaskGroup(of: (Int, PingResult).self) { group in
            var out = list
            var next = 0
            while next < min(12, list.count) {
                let i = next; next += 1
                let a = list[i].address
                group.addTask { (i, await ping(a)) }
            }
            while let r = await group.next() {
                out[r.0].pingMs = r.1.ms
                out[r.0].pinged = true
                tally[r.1.how, default: 0] += 1
                if let progress { await progress(list[r.0].address, r.1.ms) }
                if next < list.count {
                    let i = next; next += 1
                    let a = list[i].address
                    group.addTask { (i, await ping(a)) }
                }
            }
            return out
        }
        if let note {
            let ok = (tally["icmp"] ?? 0) + (tally["ike"] ?? 0)
            await note("ping: \(ok)/\(list.count) answered (ike \(tally["ike"] ?? 0), icmp \(tally["icmp"] ?? 0), dns-fail \(tally["dns"] ?? 0), silent \(tally["none"] ?? 0))")
        }
        return out
    }

    // MARK: probes
    private static func probe(_ host: String) -> PingResult {
        guard let addr = resolve(host) else { return PingResult(ms: nil, how: "dns") }
        if let ms = ikeProbe(addr) { return PingResult(ms: ms, how: "ike") }
        if let ms = icmp(addr) { return PingResult(ms: ms, how: "icmp") }
        return PingResult(ms: nil, how: "none")
    }

    private static func resolve(_ host: String) -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let ai = res else { return nil }
        defer { freeaddrinfo(res) }
        guard Int(ai.pointee.ai_addrlen) >= MemoryLayout<sockaddr_in>.size, let sa = ai.pointee.ai_addr else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    private static func setTimeout(_ fd: Int32, _ sec: Double) {
        var tv = timeval(tv_sec: Int(sec), tv_usec: Int32((sec - Double(Int(sec))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func sendTo(_ fd: Int32, _ bytes: [UInt8], _ addr: sockaddr_in) -> Bool {
        var a = addr
        return bytes.withUnsafeBytes { p in
            withUnsafePointer(to: &a) { ap in
                ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    sendto(fd, p.baseAddress, p.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size)) > 0
                }
            }
        }
    }

    private static func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    private static func icmp(_ addr: sockaddr_in) -> Int? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        setTimeout(fd, 1.5)

        var pkt = [UInt8](repeating: 0, count: 16)
        pkt[0] = 8; pkt[7] = 1                       // echo request, seq 1
        var sum: UInt32 = 0
        var i = 0
        while i < pkt.count { sum += (UInt32(pkt[i]) << 8) | UInt32(pkt[i + 1]); i += 2 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        let ck = ~UInt16(truncatingIfNeeded: sum)
        pkt[2] = UInt8(ck >> 8); pkt[3] = UInt8(ck & 0xff)

        let t0 = nowNs()
        guard sendTo(fd, pkt, addr) else { return nil }
        var buf = [UInt8](repeating: 0, count: 256)
        while nowNs() - t0 < 1_500_000_000 {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { return nil }
            let ihl = (buf[0] >> 4) == 4 ? Int(buf[0] & 0x0f) * 4 : 0   // reply may include the IP header
            if n > ihl, buf[ihl] == 0 { return max(Int((nowNs() - t0) / 1_000_000), 1) }
        }
        return nil
    }

    /// The same 248-byte IKE_SA_INIT request the Android app sends (AES128-CBC / HMAC-SHA1 / MODP1024).
    private static func ikeInit() -> [UInt8] {
        func rnd(_ n: Int) -> [UInt8] {
            var b = [UInt8](repeating: 0, count: n)
            _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
            return b
        }
        func u16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
        func u32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }

        var ke = rnd(128)
        ke[0] &= 0x7f

        var out = rnd(8)                                   // initiator SPI
        out += [UInt8](repeating: 0, count: 8)             // responder SPI
        out += [33, 0x20, 34, 0x08]                        // next=SA, v2.0, IKE_SA_INIT, initiator flag
        out += u32(0); out += u32(248)                     // message id, length
        // SA payload (48 bytes) with one proposal and four transforms
        out += [34, 0]; out += u16(48)
        out += [0, 0]; out += u16(44); out += [1, 1, 0, 4]
        out += [3, 0]; out += u16(12); out += [1, 0]; out += u16(12); out += u16(0x800E); out += u16(128)   // ENCR AES-CBC, 128 bit
        out += [3, 0]; out += u16(8); out += [2, 0]; out += u16(2)                                         // PRF HMAC-SHA1
        out += [3, 0]; out += u16(8); out += [3, 0]; out += u16(2)                                         // INTEG HMAC-SHA1-96
        out += [0, 0]; out += u16(8); out += [4, 0]; out += u16(2)                                         // DH MODP-1024
        // KE payload (136 bytes)
        out += [40, 0]; out += u16(136); out += u16(2); out += u16(0); out += ke
        // Nonce payload (36 bytes)
        out += [0, 0]; out += u16(36); out += rnd(32)
        return out
    }

    private static func ikeProbe(_ addr: sockaddr_in) -> Int? {
        var a = addr
        a.sin_port = UInt16(500).bigEndian
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        setTimeout(fd, 1.5)
        let pkt = ikeInit()
        let t0 = nowNs()
        guard sendTo(fd, pkt, a) else { return nil }
        var buf = [UInt8](repeating: 0, count: 2048)
        let n = recv(fd, &buf, buf.count, 0)
        guard n >= 28 else { return nil }
        return max(Int((nowNs() - t0) / 1_000_000), 1)
    }
}
