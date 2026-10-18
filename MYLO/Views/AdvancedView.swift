#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI

struct AdvancedView: View {
    @EnvironmentObject var vm: VpnViewModel
    var onBack: () -> Void
    var onImport: () -> Void = {}
    @State private var issuer = Store.shared.issuerCN
    @State private var acctUser = Store.shared.user
    @State private var acctPass = Store.shared.pass
    @State private var shortcutsReady = Store.shared.shortcutsReady

    var body: some View {
        VStack(spacing: 0) {
            SubHeader("Advanced", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !Defaults.requireLogin {
                        Text("IKEv2 account").foregroundColor(C.muted)
                        TextField("Username", text: $acctUser)
#if canImport(UIKit)
                            .autocapitalization(.none)
#endif
                            .autocorrectionDisabled().foregroundColor(C.ink)
                            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(C.card))
                            .onValueChange(of: acctUser) { Store.shared.user = $0.trimmingCharacters(in: .whitespaces) }
                        SecureField("Password", text: $acctPass)
#if canImport(UIKit)
                            .autocapitalization(.none)
#endif
                            .autocorrectionDisabled().foregroundColor(C.ink)
                            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(C.card))
                            .onValueChange(of: acctPass) { Store.shared.pass = $0 }
                        Text("Entered once, kept in the Keychain. Used for the IKEv2 profile and direct mode.")
                            .font(.mylo(12)).foregroundColor(C.muted)
                    }
                    #if !APPSTORE
                    Button(action: onImport) {
                        Text("Add VLESS / VMess / Trojan / OpenVPN").font(.mylo(16, weight: .semibold)).foregroundColor(C.teal)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.teal, lineWidth: 1.5))
                    }
                    #endif
                    Text("IKEv2").foregroundColor(C.muted).padding(.top, 8)
                    TextField("Server certificate issuer CN (optional)", text: $issuer)
#if canImport(UIKit)
                        .autocapitalization(.none)
#endif
                        .autocorrectionDisabled().foregroundColor(C.ink)
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(C.card))
                        .onValueChange(of: issuer) { Store.shared.issuerCN = $0.trimmingCharacters(in: .whitespaces) }
                    Text("iOS cannot load a CA file inside the app. If the server certificate is not signed by a CA iOS already trusts, install the CA as a profile (Settings > General > VPN & Device Management) and enable it under Settings > General > About > Certificate Trust Settings.")
                        .font(.mylo(12)).foregroundColor(C.muted)

                    Text("Diagnostics").foregroundColor(C.muted).padding(.top, 8)
                    HStack {
                        Text("Personal VPN entitlement").foregroundColor(C.ink)
                        Spacer()
                        switch Diag.hasVpnEntitlement() {
                        case .some(true): Text("present").foregroundColor(C.teal)
                        case .some(false): Text("missing").foregroundColor(C.danger)
                        case .none: Text("unknown").foregroundColor(C.muted)
                        }
                    }
                    Text(vm.mode == .profile
                         ? "This build has no Personal VPN entitlement (free Apple ID). MYLO installs a VPN profile and you switch it on in Settings > VPN."
                         : "The app controls the VPN directly.")
                        .font(.mylo(12)).foregroundColor(C.muted)

                    #if !APPSTORE
                    if vm.mode == .profile {
                        Text("One-tap connect (Shortcuts)").foregroundColor(C.muted).padding(.top, 8)
                        Text("iOS only lets this app switch the VPN on through the Shortcuts app. Create two shortcuts once:\n1. Shortcuts > + > name it \"\(Defaults.shortcutOn)\" > add the action \"Set VPN\" > Connect > choose MYLO VPN.\n2. Another one named \"\(Defaults.shortcutOff)\" with \"Set VPN\" > Disconnect.\nThen switch the option below on. The power button then turns the VPN on and off (it flashes Shortcuts for a second).")
                            .font(.mylo(12)).foregroundColor(C.muted)
                        Button { vm.openShortcutsApp() } label: {
                            Text("Open Shortcuts").font(.mylo(16, weight: .semibold)).foregroundColor(C.teal)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.teal, lineWidth: 1.5))
                        }
                        Toggle("I created both shortcuts", isOn: $shortcutsReady)
                            .tint(C.teal).foregroundColor(C.ink)
                            .onValueChange(of: shortcutsReady) { Store.shared.shortcutsReady = $0 }
                    }

                    Text("VPN profile").foregroundColor(C.muted).padding(.top, 8)
                    Button { vm.installProfileNow() } label: {
                        Text("Install / update VPN profile (opens Safari)").font(.mylo(16, weight: .semibold))
                            .foregroundColor(Pal.shared.cur.dark ? Color.black : Color.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(C.teal))
                    }
                    Text("Tap Allow in Safari, then Settings > Profile Downloaded > Install. Settings > VPN always shows a single entry, \"MYLO VPN\". It is only reinstalled (and replaced) when you change the location or the account.")
                        .font(.mylo(12)).foregroundColor(C.muted)
                    Button { Diag.openVpnSettings() } label: {
                        Text("Open iOS VPN settings").font(.mylo(16, weight: .semibold)).foregroundColor(C.teal)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.teal, lineWidth: 1.5))
                    }
                    #endif
                    Text("Changes apply on the next connect.").font(.mylo(12)).foregroundColor(C.muted).padding(.top, 8)
                }
                .padding(20)
            }
        }
    }
}
