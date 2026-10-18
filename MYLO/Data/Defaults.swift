import Foundation

/// Static configuration. The VPN account is NOT stored here: it arrives encrypted after login (see Auth.swift).
enum Defaults {
    /// https address of users.json (made by tools/mylo_users.py). Example: "https://YOUR-DOMAIN/mylo/users.json"
    /// Leave "" to use only `embeddedUsers`.
    static let authURL = ""

    /// false = no login screen: the app opens straight to the VPN page.
    /// true  = the old username/password gate (users.json) comes back.
    static let requireLogin = false

    /// IKEv2 account used when the login screen is off. Leave empty and enter it once in Profile > Advanced
    /// instead (it is then kept in the Keychain). Anything written here is readable by anyone who unpacks the IPA.
    static let vpnUser = ""
    static let vpnPass = ""

    /// Names of the two Shortcuts the user creates once (action "Set VPN" > Connect / Disconnect "MYLO VPN").
    static let shortcutOn = "MYLO On"
    static let shortcutOff = "MYLO Off"

    /// Profile mode only. iOS gives an app no API to read the state of a VPN profile installed from Settings, so
    /// "Protected" can only come from observing that internet traffic really leaves through a tunnel interface.
    /// Set to false to be even stricter: profile mode then never shows "Protected" (it only guides the user).
    static let profileAutoDetect = true

    /// Optional: paste the whole content of users.json here. Used when authURL is empty or unreachable.
    static let embeddedUsers = ""

    static let rid = "pointtoserver.com"

    // cc|host-prefix  (full host = prefix + ".ptoserver.com" unless the prefix already contains a dot)
    private static let list = """
TR|sx160591-ikev
TR|tr2-auto-ikev
SE|se2-auto-ikev
CH|ch2-auto-ikev
NL|nl2-auto-ikev
DE|eg2-auto-ikev
DE|om2-auto-ikev
RO|sx070667-ikev
NO|no2-auto-ikev
GB|ukl2-auto-ikev
AT|at2-auto-ikev
DE|mc2-auto-ikev
GB|ukm2-auto-ikev
DE|pr2-auto-ikev
SE|sx060289-ikev
IE|ie2-auto-ikev
BE|be-ikev-pf
GB|uk2-auto-ikev
FR|fr2-auto-ikev
LU|lu-ikev
LT|lt-ikev
IT|it-ikev-pf
SK|sk2-auto-ikev
HU|hu2-auto-ikev
LV|lv2-auto-ikev
EE|ee2-auto-ikev
BG|bg-ikev
DK|dk-ikev
PT|pt2-auto-ikev
DE|de2-auto-ikev
US|us2-auto-ikev
CA|cato2-auto-ikev
NG|ng2-auto-ikev
US|sx017451-ikev
CA|cav2-auto-ikev
RS|rs-ikev
US|vg-ikev
US|usfl2-auto-ikev
AE|ae2-auto-ikev
US|bo2-auto-ikev
NL|in2-auto-ikev
US|sx0112801-ikev
BN|bn-ikev
US|ussf2-auto-ikev
US|ky2-auto-ikev
CA|ca2-auto-ikev
ZA|za-ikev
US|bm2-auto-ikev
SG|sg-ikev-pf
US|pa2-auto-ikev
SG|ph2-auto-ikev
US|usphx2-auto-ikev
US|ustx2-auto-ikev
US|aw2-auto-ikev
CL|cl2-auto-ikev
HK|hk2-auto-ikev
BR|br-ikev
AR|ar2-auto-ikev
JP|jp-ikev-pf
KR|kr2-auto-ikev
AU|aubn2-auto-ikev
US|uswdc2-auto-ikev
AU|au2-auto-ikev
AU|aume2-auto-ikev
AU|ausd2-auto-ikev
US|usga2-auto-ikev
US|usnj2-auto-ikev
US|usva2-auto-ikev
US|usil2-auto-ikev
US|usny2-auto-ikev
US|ussa2-auto-ikev
US|usut2-auto-ikev
AU|aupe2-auto-ikev
US|usca2-auto-ikev
GR|gr2-auto-ikev
US|ao2-auto-ikev
US|bb2-auto-ikev
US|sx013365-ikev
US|sx017451-ikev
US|sx019630-ikev
US|sx017501-ikev
US|sx0140122-ikev
US|sx019543-ikev
AU|sx152501-ikev
AU|sx152610-ikev
AU|sx152416-ikev
AU|sx152201-ikev
DE|sx0430139-ikev
CA|sx032111-ikev
CA|sx0320145-ikev
CA|sx032322-ikev
NL|sx0517119-ikev
HK|sx241130-ikev
MY|sx110990-ikev
BE|sx400501-ikev
FR|sx1730195-ikev
SE|sx060289-ikev
JP|sx331416-ikev
SG|sx121001-ikev
IT|sx250531-ikev
IT|sx250797-ikev
IE|sx1302104-ikev.dnsdialer.com
LU|sx140301-ikev
IN|sx591801-ikev
AT|sx490305-ikev
DK|sx410701-ikev
NO|sx420632-ikev
RO|sx070682-ikev
RU|sx100837-ikev
RU|sx101031-ikev
PL|sx380101-ikev
CZ|sx390434-ikev
FI|sx470502-ikev
ES|sx460484-ikev
CH|sx080619-ikev
UA|sx230201-ikev
NZ|sx340546-ikev
MX|sx360633-ikev
"""

    /// All servers, de-duplicated by address, named "Country" or "Country - n".
    static func servers() -> [Server] {
        var order: [String] = []
        var ccOf: [String: String] = [:]
        for raw in list.split(whereSeparator: \.isNewline) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if f.count < 2 { continue }
            let host = f[1].contains(".") ? f[1] : f[1] + ".ptoserver.com"
            if ccOf[host] == nil { ccOf[host] = f[0]; order.append(host) }
        }
        var total: [String: Int] = [:]
        for h in order { total[ccOf[h]!, default: 0] += 1 }
        var idx: [String: Int] = [:]
        return order.map { host in
            let cc = ccOf[host]!
            let k = (idx[cc] ?? 0) + 1
            idx[cc] = k
            let base = cc.isEmpty ? "Other" : countryName(cc)
            let name = (total[cc] ?? 1) > 1 ? "\(base) - \(k)" : base
            return Server(name: name, address: host, cc: cc)
        }
    }
}

// MARK: - Helper
extension Defaults {
    static func countryName(_ cc: String) -> String {
        let dict: [String: String] = [
            "TR": "Turkey", "SE": "Sweden", "CH": "Switzerland", "NL": "Netherlands",
            "DE": "Germany", "RO": "Romania", "NO": "Norway", "GB": "United Kingdom",
            "AT": "Austria", "IE": "Ireland", "BE": "Belgium", "FR": "France",
            "LU": "Luxembourg", "LT": "Lithuania", "IT": "Italy", "SK": "Slovakia",
            "HU": "Hungary", "LV": "Latvia", "EE": "Estonia", "BG": "Bulgaria",
            "DK": "Denmark", "PT": "Portugal", "US": "United States", "CA": "Canada",
            "NG": "Nigeria", "RS": "Serbia", "VG": "British Virgin Islands",
            "AE": "United Arab Emirates", "BN": "Brunei", "SG": "Singapore",
            "ZA": "South Africa", "CL": "Chile", "HK": "Hong Kong",
            "BR": "Brazil", "AR": "Argentina", "JP": "Japan", "KR": "South Korea",
            "AU": "Australia", "GR": "Greece", "AO": "Angola", "BB": "Barbados",
            "IN": "India", "RU": "Russia", "PL": "Poland", "CZ": "Czech Republic",
            "FI": "Finland", "ES": "Spain", "UA": "Ukraine", "NZ": "New Zealand",
            "MX": "Mexico"
        ]
        return dict[cc] ?? "Unknown"
    }
}