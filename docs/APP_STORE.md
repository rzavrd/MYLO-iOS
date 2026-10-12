# Publishing MYLO VPN on the App Store

Everything below is a checklist. Nothing here was built, signed or submitted for you.

## 1. Requirements you cannot skip
- **Paid Apple Developer Program membership.** A free Apple ID cannot upload to App Store Connect.
- **Organization enrollment.** Guideline 5.4 says VPN apps must be submitted by a developer enrolled as an organization (a D-U-N-S number is needed). Individual accounts are rejected for VPN apps.
- **Personal VPN capability** on your App ID (Certificates, Identifiers & Profiles > Identifiers > your Bundle ID > Personal VPN). `MYLO-AppStore` already carries the entitlement `com.apple.developer.networking.vpn.api = allow-vpn`.

## 2. Build the App Store target
```
brew install xcodegen && xcodegen && open MYLO.xcodeproj
```
- Scheme **MYLO-AppStore**, your Team, your own unique Bundle ID (change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, then run `xcodegen` again).
- This target is compiled with `APPSTORE`: always native mode (`NEVPNManager`), no profile installer, no local HTTP server, no Shortcuts flow, no VLESS/VMess/Trojan/OpenVPN import screen (those cannot connect yet and unfinished features get rejected under guideline 2.1).
- Product > Archive > Distribute App > App Store Connect.

## 3. Things that will get the app rejected if left as they are
1. **Server list and account.** `Defaults.swift` lists hostnames of a third-party provider. Use your own servers, or make sure you are allowed to use that provider's name, servers and accounts commercially. The app also needs a *working* account for the reviewer.
2. **Demo account.** App Store Connect > App Review Information: put a working IKEv2 username/password (and the steps: Profile > Advanced > IKEv2 account) so the reviewer can connect.
3. **Misleading claims.** Don't promise anonymity, "100% secure" or unblocking; don't mention circumventing a government's blocking.
4. **Data use.** Guideline 5.4: no selling or sharing user data, no collecting it for anything but the VPN function. Say so in the privacy policy.
5. **Regional laws.** VPN apps are restricted in some countries (for example China, Russia, UAE, Turkey, Iran). Apple can require a license or remove the app there. Check where you list it (App Store Connect > Pricing and Availability).
6. **Placeholder icon.** `Assets.xcassets/AppIcon` is a simple generated icon. Replace it with your own 1024x1024 PNG (no transparency).

## 4. App Store Connect form
- **Privacy policy URL**: required. Start from `docs/PRIVACY.md` and host it (GitHub Pages works).
- **App Privacy ("nutrition label")**: the app itself collects nothing. It does contact `api.ipify.org` to show your public IP and sends pings/TCP probes to Cloudflare/Google/Quad9; if you keep these, mention them. `PrivacyInfo.xcprivacy` declares no tracking and the two required-reason APIs used (UserDefaults, boot time).
- **Export compliance**: `ITSAppUsesNonExemptEncryption` is set to `false` (only operating-system IKEv2 and standard CryptoKit are used). Confirm this fits your situation; if unsure ask a lawyer.
- **Age rating**, category (Utilities), screenshots (6.7" and 6.1" iPhone), description, support URL, contact info.
- **Review notes** template:
  > MYLO VPN is an IKEv2 VPN client using the Network Extension Personal VPN API (NEVPNManager). Sign-in: Profile > Advanced > IKEv2 account, username `…`, password `…`. Then tap the power button on the VPN tab; iOS asks to add a VPN configuration, tap Allow. The app collects no personal data.

## 5. What is deliberately not in the App Store build
The `MYLO-OpenVPN` target and its AGPL core (see docs/OPENVPN.md).
VLESS / VMess / Trojan / OpenVPN need a Packet Tunnel extension and a VPN core (Xray, sing-box, OpenVPN). Until that exists, keep them in the open-source (free Apple ID) target only.

## 6. Open source + App Store
MIT is compatible with App Store distribution. If you later bundle GPL code (for example an OpenVPN core), the licenses conflict with App Store terms: check each core's license first.
