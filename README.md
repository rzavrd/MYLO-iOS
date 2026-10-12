# MYLO VPN for iPhone

SwiftUI iOS client (IKEv2) with live stats, server list, speed test and config import.
Persian documentation: [README.fa.md](README.fa.md).

## Build
1. Xcode 15+, iOS 16+. `brew install xcodegen && xcodegen && open MYLO.xcodeproj`
2. Build Settings: Swift Language Version = Swift 5; set *Default Actor Isolation* to nonisolated if shown.
3. Signing: your own Team and a unique Bundle ID (`project.yml`). Run on a real device.

## Before you publish a fork
- You must supply your own IKEv2 account and server list. `Defaults.swift` contains no credentials; enter the account in Profile > Advanced, or set `Defaults.vpnUser/vpnPass` (extractable from the IPA, so don't ship them).
- `Defaults.servers()` lists third-party provider hostnames. Replace them with your own and make sure you may use them.
- The optional login (`Defaults.requireLogin = true`) uses an encrypted `users.json` made by `tools/mylo_users.py`. Never commit `tools/users.private.json` or `dist/`.

## Connection modes
- **Native** (paid Apple Developer account, Personal VPN capability): the power button connects directly through `NEVPNManager`.
- **Profile** (free Apple ID, no paid account needed): the first tap installs ONE profile, a single entry "MYLO VPN" in Settings > VPN (changing location replaces that same entry). iOS gives apps no way to switch such a VPN on, so you create two Shortcuts once ("MYLO On" / "MYLO Off", action *Set VPN*) and the power button runs them; status is then confirmed by route proof. Free-signed builds expire after 7 days.

## Connection status rules
`Protected` is shown only when `VpnController.declareConnected` is called, with one of two evidence sources:
1. `nativeStatus`: `NEVPNManager` reports connected for the tunnel this app configured.
2. `routeProof` (profile mode): ordinary internet traffic really leaves through a tunnel interface, on two consecutive samples (`NetIf.defaultRouteInterface()`).

None of these alone means Protected: installed profile, an existing `utun` (even with an IP), internet reachable, ping/TCP success.
iOS gives apps without the entitlement no API to read a Settings-installed profile, so route proof shows that *a* VPN carries traffic, not that it is MYLO's. Set `Defaults.profileAutoDetect = false` to never show Protected in profile mode.

## OpenVPN
Target `MYLO-OpenVPN` (+ extension `MYLOTunnel`) connects imported `.ovpn` profiles. Needs a paid account and has an AGPL caveat: read [docs/OPENVPN.md](docs/OPENVPN.md).

## VLESS / VMess / Trojan / OpenVPN import
Profile > Add configuration imports links, base64 subscriptions and `.ovpn` files (many files or a whole folder at once) (secrets in the Keychain). **VLESS/VMess/Trojan cannot connect yet** (they need a Packet Tunnel extension with an Xray/sing-box core); OpenVPN connects only in the `MYLO-OpenVPN` target. `ConfigStore.singBoxJSON(for:)` already produces a sing-box config. Contributions welcome.

## App Store
A second target, `MYLO-AppStore`, builds the native-only variant (Personal VPN entitlement, privacy manifest, no profile hacks, no unfinished import UI). Read [docs/APP_STORE.md](docs/APP_STORE.md) first: it needs a paid, organization-level Apple Developer account.

## Limits
No split tunneling (iOS gives no custom routes to the built-in IKEv2 client); stats and failover only while the app is open.

## License
MIT, see [LICENSE](LICENSE).
