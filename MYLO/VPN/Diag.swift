import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import LocalAuthentication

enum Diag {
    /// Whether the provisioning profile embedded in this build grants the Personal VPN entitlement.
    /// nil = cannot tell (e.g. App Store / Simulator builds have no embedded profile).
    static func hasVpnEntitlement() -> Bool? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .isoLatin1),
              let a = s.range(of: "<?xml"),
              let b = s.range(of: "</plist>") else { return nil }
        return s[a.lowerBound..<b.upperBound].contains("com.apple.developer.networking.vpn.api")
    }

    /// iOS has no Settings deep link that is guaranteed to work, so try the usual ones in turn.
    @MainActor
    static func openVpnSettings() {
#if canImport(UIKit)
        let candidates = ["App-Prefs:root=General&path=VPN", "App-Prefs:VPN", UIApplication.openSettingsURLString]
#else
        let candidates: [String] = []
#endif
        func attempt(_ i: Int) {
            guard i < candidates.count, let u = URL(string: candidates[i]) else { return }
#if canImport(UIKit)
            UIApplication.shared.open(u, options: [:]) { ok in if !ok { attempt(i + 1) } }
#elseif canImport(AppKit)
            NSWorkspace.shared.open(u)
#endif
        }
        attempt(0)
    }
}

/// The four device checks of the "Secure Device Assistant" (iOS flavour).
struct Check {
    var title: String
    var desc: String
    var ok: Bool
    var detail: String? = nil
    var subTitle: String? = nil
    var subDesc: String? = nil
    var subOk: Bool = true
}

func deviceChecks() -> [Check] {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let versionText = "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"

    let ctx = LAContext()
    var err: NSError?
    let locked = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    let bio = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)

    var jailbroken = false
    #if !targetEnvironment(simulator)
    let paths = ["/Applications/Cydia.app", "/Library/MobileSubstrate/MobileSubstrate.dylib", "/bin/bash",
                 "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/apt/", "/var/jb", "/Applications/Sileo.app"]
    jailbroken = paths.contains { FileManager.default.fileExists(atPath: $0) }
    if !jailbroken {
        let probe = "/private/mylo_jb_probe.txt"
        if (try? "x".write(toFile: probe, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(atPath: probe)
            jailbroken = true
        }
    }
    #endif

    return [
        Check(title: "Latest iOS version",
              desc: "Installing recent iOS updates keeps your device safe from known vulnerabilities. Check Settings > General > Software Update.",
              ok: v.majorVersion >= 17, detail: "You are on \(versionText)"),
        Check(title: "Passcode enabled",
              desc: "A passcode protects your data if the phone is lost or stolen.", ok: locked, detail: nil,
              subTitle: "Device encryption",
              subDesc: "iOS encrypts storage automatically once a passcode is set.", subOk: locked),
        Check(title: "Face ID / Touch ID enabled",
              desc: "Biometric unlock gives quick and secure device access.", ok: bio),
        Check(title: jailbroken ? "Jailbreak: detected" : "Jailbreak: not detected",
              desc: "Jailbroken devices are more vulnerable to malware, data theft and unauthorized access. Restore the phone to stay secure.",
              ok: !jailbroken),
    ]
}
