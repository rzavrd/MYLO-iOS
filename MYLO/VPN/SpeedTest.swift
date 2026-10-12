import Foundation

/// Counts bytes of many parallel transfers; restarts a transfer when it ends (until `onDone` is cleared).
final class SpeedMeter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _total: Int64 = 0
    var onDone: (() -> Void)?

    var total: Int64 { lock.lock(); defer { lock.unlock() }; return _total }
    private func add(_ n: Int64) { lock.lock(); _total += n; lock.unlock() }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { add(Int64(data.count)) }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) { add(bytesSent) }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { onDone?() }
}

/// Real speed test against Cloudflare's public speed endpoints. Goes through the VPN when connected.
@MainActor
final class SpeedTest: ObservableObject {
    @Published var running = false
    @Published var phase = ""
    @Published var liveMbps = 0.0
    @Published var down: Double?
    @Published var up: Double?
    @Published var latency: Int?
    @Published var jitter: Int?
    @Published var loss: Int?
    @Published var endpointIp: String?
    @Published var country: String?
    @Published var provider: String?
    @Published var ip: String?
    @Published var error: String?

    private var job: Task<Void, Never>?
    private let host = "speed.cloudflare.com"

    func start() {
        if running { return }
        job = Task { await run() }
    }

    func stop() {
        job?.cancel()
        running = false; phase = ""; liveMbps = 0
    }

    private func run() async {
        running = true; phase = "Preparing"; liveMbps = 0; error = nil
        down = nil; up = nil; latency = nil; jitter = nil; loss = nil; endpointIp = nil
        await loadInfo()
        await measureLatency()
        if !Task.isCancelled { await transfer(down: true) }
        if !Task.isCancelled { await transfer(down: false) }
        if !Task.isCancelled && error == nil { phase = "Done" }
        running = false
        liveMbps = 0
    }

    private func loadInfo() async {
        guard let url = URL(string: "https://ipinfo.io/json") else { return }
        var req = URLRequest(url: url); req.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        ip = o["ip"] as? String
        country = o["country"] as? String
        var org = (o["org"] as? String) ?? ""
        if org.hasPrefix("AS"), let sp = org.firstIndex(of: " ") { org = String(org[org.index(after: sp)...]) }
        provider = org
    }

    private func measureLatency() async {
        phase = "Latency"
        endpointIp = Probe.resolveIPv4(host)
        var times: [Int] = []
        var lost = 0
        for _ in 0..<10 {
            if Task.isCancelled { return }
            if let ms = await Probe.tcpLatency(host: host, port: 443) { times.append(ms) } else { lost += 1 }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        latency = times.isEmpty ? nil : times.reduce(0, +) / times.count
        if times.count > 1 {
            var s = 0
            for i in 1..<times.count { s += abs(times[i] - times[i - 1]) }
            jitter = s / (times.count - 1)
        } else { jitter = 0 }
        loss = lost * 10
    }

    private func transfer(down isDown: Bool) async {
        phase = isDown ? "Download" : "Upload"
        liveMbps = 0
        let meter = SpeedMeter()
        let session = URLSession(configuration: .ephemeral, delegate: meter, delegateQueue: nil)
        let body = Data(repeating: 0x55, count: 8_000_000)
        let host = self.host
        let start = Date()
        let end = start.addingTimeInterval(isDown ? 8 : 6)

        func launch() {
            if Date() >= end { return }
            if isDown {
                if let u = URL(string: "https://\(host)/__down?bytes=50000000") { session.dataTask(with: URLRequest(url: u)).resume() }
            } else if let u = URL(string: "https://\(host)/__up") {
                var r = URLRequest(url: u)
                r.httpMethod = "POST"
                session.uploadTask(with: r, from: body).resume()
            }
        }
        meter.onDone = { launch() }
        for _ in 0..<4 { launch() }

        var last: Int64 = 0
        var lastT = start
        while Date() < end && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let now = Date()
            let b = meter.total
            let dt = max(now.timeIntervalSince(lastT), 0.05)
            liveMbps = Double(b - last) * 8 / dt / 1e6
            last = b; lastT = now
        }
        meter.onDone = nil
        session.invalidateAndCancel()
        let secs = max(Date().timeIntervalSince(start), 0.5)
        let avg = Double(meter.total) * 8 / secs / 1e6
        if isDown { down = avg } else { up = avg }
        if meter.total == 0 && !Task.isCancelled { error = "No data received - check your connection." }
        liveMbps = 0
    }
}
