import Foundation

func fmtBits(_ bytesPerSec: Int64) -> String {
    let bits = Double(bytesPerSec) * 8
    if bits >= 1e6 { return String(format: "%.1f Mbps", bits / 1e6) }
    if bits >= 1e3 { return String(format: "%.0f Kbps", bits / 1e3) }
    return String(format: "%.0f bps", bits)
}

func fmtBytes(_ b: Int64) -> String {
    let d = Double(b)
    if b >= 1 << 30 { return String(format: "%.2f GB", d / 1_073_741_824) }
    if b >= 1 << 20 { return String(format: "%.1f MB", d / 1_048_576) }
    if b >= 1 << 10 { return String(format: "%.0f KB", d / 1024) }
    return "\(b) B"
}

func fmtDur(_ sec: Int) -> String {
    String(format: "%02d:%02d:%02d", sec / 3600, sec % 3600 / 60, sec % 60)
}

func flagEmoji(_ cc: String) -> String {
    let u = cc.uppercased()
    guard u.count == 2, u.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "\u{1F310}" }
    var s = ""
    for sc in u.unicodeScalars { if let f = UnicodeScalar(127397 + sc.value) { s.unicodeScalars.append(f) } }
    return s
}

func countryName(_ cc: String) -> String {
    guard cc.count == 2 else { return "Other" }
    return Locale(identifier: "en").localizedString(forRegionCode: cc.uppercased()) ?? cc
}

/// Country code from a hostname prefix like "uk2-auto-ikev..." -> GB. Empty if unknown.
func guessCc(_ host: String) -> String {
    if host.hasPrefix("sx") { return "" }
    var c = String(host.prefix(2)).uppercased()
    if c == "UK" { c = "GB" }
    return Locale.Region.isoRegions.contains(where: { $0.identifier == c }) ? c : ""
}

/// Country code for an imported config: a leading code ("us-east", "uk_london"), else a country name inside the
/// file name ("Germany-udp", "Hong Kong"), else the host prefix. Empty if unknown.
func configCc(_ name: String, host: String) -> String {
    let n = name.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    let lead = String(n.prefix(while: { $0.isLetter }))
    if lead.count == 2 {
        let c = lead == "uk" ? "GB" : lead.uppercased()
        if CountryNames.byCode[c] != nil { return c }
    }
    var best: (len: Int, cc: String)?
    for (cc, nm) in CountryNames.byCode where n.contains(nm) {
        if best == nil || nm.count > best!.len { best = (nm.count, cc) }
    }
    if let b = best { return b.cc }
    return guessCc(host)
}

private enum CountryNames {
    /// "US" -> "united states" (lower case English names, built once).
    static let byCode: [String: String] = {
        var d: [String: String] = [:]
        let en = Locale(identifier: "en")
        for r in Locale.Region.isoRegions where r.identifier.count == 2 {
            if let nm = en.localizedString(forRegionCode: r.identifier) { d[r.identifier] = nm.lowercased() }
        }
        d["US"] = "united states"; d["GB"] = "united kingdom"
        return d
    }()
}

/// label + signal bars (0...3) from a ping in ms
func quality(_ ms: Int?) -> (label: String, bars: Int) {
    guard let ms = ms else { return ("", 0) }
    if ms < 100 { return ("Great", 3) }
    if ms < 180 { return ("Good", 3) }
    if ms < 300 { return ("Fair", 2) }
    if ms < 500 { return ("Bad", 1) }
    return ("Very bad", 1)
}

enum Regions {
    static let names = ["All Regions", "Europe", "Americas", "Asia Pacific", "Middle East", "Africa"]
    static func of(_ cc: String) -> String {
        switch cc.uppercased() {
        case "US", "CA", "BR", "AR", "CL", "MX": return "Americas"
        case "SG", "HK", "JP", "KR", "AU", "NZ", "BN", "IN", "TH", "MY", "ID": return "Asia Pacific"
        case "AE", "TR", "IL", "SA": return "Middle East"
        case "NG", "ZA", "EG": return "Africa"
        default: return "Europe"
        }
    }
}
