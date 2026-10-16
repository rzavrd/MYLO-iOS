import UIKit
import SwiftUI

private let faq: [(String, String)] = [
    ("I can't connect",
     "Open Profile > Connection Log: it shows the exact error (for example AUTHENTICATION FAILED means the VPN account or the remote ID was refused). Try another location and make sure UDP ports 500 and 4500 are not blocked by your network."),
    ("The power button only installs a profile",
     "Apps signed with a free Apple ID cannot control the VPN. MYLO then installs a VPN profile for the selected location; switch \"MYLO VPN\" on in Settings > VPN. MYLO shows the status, speed and usage while it is on. With a paid Apple Developer account (Personal VPN) the power button connects directly."),
    ("Iranian sites don't open while connected",
     "iOS sends all traffic through the VPN: the built-in IKEv2 client cannot exclude IP ranges, so there is no split tunneling. Switch the VPN off when you need Iranian sites."),
    ("My internet stops when the VPN drops",
     "In direct mode MYLO checks the tunnel every few seconds. If it is dead it stops the VPN so your normal internet comes back and (with Auto reconnect on) connects to the fastest other location. In profile mode iOS itself manages the tunnel."),
    ("What is the Live ping?",
     "On the home screen, 'direct' is the latency of your real connection (without the VPN); it pauses while the VPN is on. 'Via VPN' is the round trip through the tunnel."),
    ("Who can use this app?",
     "Only accounts created by the owner. If your access is removed or expires, the app signs you out the next time it can verify your account."),
]

struct HelpView: View {
    var go: (String) -> Void
    @State private var open: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Help").font(.mylo(22, weight: .bold)).foregroundColor(C.ink).padding(.top, 4)
                ForEach(0..<faq.count, id: \.self) { i in
                    Button { open = (open == i) ? nil : i } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(faq[i].0).font(.mylo(17, weight: .semibold)).foregroundColor(C.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: open == i ? "chevron.up" : "chevron.down").foregroundColor(C.ink)
                            }
                            if open == i {
                                Text(faq[i].1).font(.mylo(14)).foregroundColor(C.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                            }
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                }
                Button { go("log") } label: { outlined("Open connection log") }
                Button { Diag.openVpnSettings() } label: { outlined("Open iOS VPN settings") }
                Spacer().frame(height: 12)
            }
            .padding(20)
        }
    }

    private func outlined(_ t: String) -> some View {
        Text(t).font(.mylo(16, weight: .semibold)).foregroundColor(C.teal)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.teal, lineWidth: 1.5))
    }
}
