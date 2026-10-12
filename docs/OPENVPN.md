# OpenVPN support

OpenVPN on iOS needs a **Packet Tunnel Network Extension** running an OpenVPN core. That is what the `MYLO-OpenVPN` target and the `MYLOTunnel` extension are. It was written without being able to compile or run it, so treat it as untested until you have built it once.

## Requirements
- Paid Apple Developer account. In the Developer portal enable **Network Extension** (and Personal VPN) on **both** App IDs: `com.mylo.vpn` and `com.mylo.vpn.tunnel`. The tunnel id must be `<app id>.tunnel`; if you change the app id, change it in `project.yml` too.
- `brew install xcodegen && xcodegen`, then build the scheme **MYLO-OpenVPN** on a real device (Network Extensions don't run in the simulator).
- Swift Package Manager fetches [OpenVPNAdapter](https://github.com/ss-abramchuk/OpenVPNAdapter). If resolving `from: 0.8.0` fails, edit `project.yml` to use `branch: master`. The package is not actively maintained; if it no longer builds with your Xcode, the extension can be ported to another core (the app-side code does not change).

## Use
1. Profile > Add configuration: import `.ovpn` files (several files, or a whole folder).
2. If a profile has `auth-user-pass`, tap the key icon and save the username/password.
3. Tap **Use** on the profile you want, go back to the VPN tab, tap the power button. iOS asks once to add a VPN configuration.
4. "Protected" is shown only when iOS reports the tunnel as connected (same rule as IKEv2).

The `.ovpn` text and the credentials are passed to the extension through the VPN configuration (`providerConfiguration`), which iOS stores in the system. Inline certificates/keys (`<ca>`, `<cert>`, `<key>`) are supported; references to external files are not (iOS sandbox).

## License warning
OpenVPNAdapter wraps the OpenVPN 3 core, which is **AGPL-3.0** (a commercial license is available from OpenVPN Inc.). A binary that links it must be distributed under AGPL-compatible terms, and AGPL is generally considered incompatible with App Store terms. That is why the OpenVPN code lives only in the separate `MYLOTunnel` extension and `MYLO-OpenVPN` target; the `MYLO` and `MYLO-AppStore` targets don't link it. If you publish `MYLO-OpenVPN` builds, license that build accordingly and get legal advice. Don't submit `MYLO-OpenVPN` to the App Store without a commercial OpenVPN license.

## Not implemented
- Live speed/usage statistics for OpenVPN (status, public IP and latency work).
- VLESS / VMess / Trojan (they are only saved; they need a Xray or sing-box core in the same extension).
