import UIKit
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var vm: VpnViewModel
    @EnvironmentObject var auth: AuthModel
    var go: (String) -> Void
    @State private var dialog: String?
    @State private var confirmLogout = false

    var body: some View {
        let s = auth.session
        ScrollView {
            VStack(spacing: 0) {
                Text("Profile").font(.mylo(22, weight: .bold)).foregroundColor(C.ink)
                    .frame(maxWidth: .infinity).padding(.top, 20)

                SectionTitle("Account Details")
                if Defaults.requireLogin {
                    SettingRow(icon: "person.fill", title: "Signed in as", value: s?.name ?? "-")
                    SettingRow(icon: "calendar", title: "Valid until", value: expiryText(s?.exp))
                }
                SettingRow(icon: "shield.fill", title: "Access", value: vm.mode == .native ? "Direct" : "iOS profile")

                SectionTitle("VPN Settings")
                Button { go("appearance") } label: {
                    SettingRow(icon: "paintpalette.fill", title: "Appearance", subtitle: "Customize your app's look and feel", value: vm.theme, chevron: true)
                }.buttonStyle(.plain)
                Button { dialog = "split" } label: {
                    SettingRow(icon: "arrow.triangle.branch", title: "Split Tunneling", subtitle: "Add IP addresses to bypass the VPN connection.", chevron: true)
                }.buttonStyle(.plain)
                ToggleRow(icon: "location.fill", title: "Show IP on Map",
                          subtitle: "Show your public IP in the connection stats. Disable to hide it.",
                          isOn: Binding(get: { vm.showIp }, set: { vm.setShowIp($0) }))
                ToggleRow(icon: "shield.lefthalf.filled", title: "Internet Kill Switch",
                          subtitle: "Sends all traffic through the tunnel so nothing leaks if it drops. Needs the direct mode; applies on the next connect.",
                          isOn: Binding(get: { vm.killSwitch }, set: { vm.setKillSwitch($0) }))
                #if !APPSTORE
                Button { go("configs") } label: {
                    SettingRow(icon: "square.and.arrow.down.fill", title: "Add configuration", subtitle: "VLESS, VMess, Trojan links and OpenVPN files", chevron: true)
                }.buttonStyle(.plain)
                #endif
                Button { dialog = "proto" } label: {
                    SettingRow(icon: "key.fill", title: "VPN Protocol", subtitle: "Choose the best protocol for your needs", value: "IKEv2", chevron: true)
                }.buttonStyle(.plain)
                ToggleRow(icon: "bolt.fill", title: "Fastest Location auto-pick",
                          subtitle: "Ping all locations and connect to the fastest. Disable to use the selected location.",
                          isOn: Binding(get: { vm.auto }, set: { vm.setAuto($0) }))
                ToggleRow(icon: "arrow.clockwise", title: "Auto reconnect",
                          subtitle: "If the tunnel dies, switch to the fastest other location (direct mode). Your normal internet is restored first.",
                          isOn: Binding(get: { vm.failover }, set: { vm.setFailover($0) }))
                ToggleRow(icon: "checkmark.shield.fill", title: "Verify connection",
                          subtitle: "After connecting, check that traffic really passes; if not, try the next option automatically.",
                          isOn: Binding(get: { vm.verify }, set: { vm.setVerify($0) }))
                Button { go("advanced") } label: {
                    SettingRow(icon: "gearshape.fill", title: "Advanced", subtitle: "Certificate, diagnostics, VPN profile", chevron: true)
                }.buttonStyle(.plain)
                Button { go("log") } label: {
                    SettingRow(icon: "terminal.fill", title: "Connection Log", subtitle: "See exactly what happened during the last connection", chevron: true)
                }.buttonStyle(.plain)
                if Defaults.requireLogin {
                    Button { confirmLogout = true } label: {
                        SettingRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign out", subtitle: "Removes the VPN account from this phone")
                    }.buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    Image("Logo").resizable().scaledToFit().frame(width: 72)
                    Text("MYLO VPN  " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                        .font(.mylo(12)).foregroundColor(C.muted)
                }
                .padding(24)
            }
        }
        .alert(dialog == "split" ? "Split Tunneling" : "VPN Protocol", isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dialog == "split"
                 ? "Sending Iranian sites outside the VPN needs control over routes, which iOS's built-in IKEv2 client does not give apps. Switch the VPN off when you need Iranian sites."
                 : "IKEv2/IPsec with EAP-MSCHAPv2. WireGuard and OpenVPN aren't included in this version.")
        }
        .alert("Sign out?", isPresented: $confirmLogout) {
            Button("Sign out", role: .destructive) { vm.onLogout(); auth.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will have to sign in again to use the VPN.")
        }
    }

    private func expiryText(_ exp: Double?) -> String {
        guard let exp else { return "No limit" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: Date(timeIntervalSince1970: exp))
    }
}
