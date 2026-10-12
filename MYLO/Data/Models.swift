import Foundation

struct Server: Codable, Identifiable, Hashable {
    var name: String
    var address: String
    var cc: String = ""
    var pingMs: Int? = nil          // runtime only, not persisted
    var pinged = false              // runtime only: a ping round finished for this server

    var id: String { address }
    enum CodingKeys: String, CodingKey { case name, address, cc }
}

struct Hist: Codable, Identifiable {
    var server: String
    var cc: String
    var start: Double               // unix seconds
    var end: Double
    var rx: Int64
    var tx: Int64
    var status: String

    var id: Double { start }
}

struct Stats {
    var downBps: Int64 = 0
    var upBps: Int64 = 0
    var rx: Int64 = 0
    var tx: Int64 = 0
    var latencyMs: Int? = nil
    var publicIp: String? = nil
    var downHist: [Int64] = []
    var upHist: [Int64] = []
}

struct LiveInfo {
    var directMs: Int? = nil
    var vpnMs: Int? = nil
}
