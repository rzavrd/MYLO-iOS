# MYLO VPN — iPhone

پورت SwiftUI از اپ اندروید MYLO VPN. صفحهٔ ورود به‌صورت پیش‌فرض خاموش است (`Defaults.requireLogin = false`).

## ورود و کنترل دسترسی
- اکانت VPN (PureVPN) **داخل اپ نیست**. بعد از ورود موفق از فایل `users.json` گرفته می‌شود که برای هر کاربر با رمز خودش رمز شده است (PBKDF2-SHA256 ← AES-256-GCM). رمز غلط = فایل باز نمی‌شود.
- مدیریت کاربرها با `tools/mylo_users.py` (نیاز: `pip install cryptography`):
  ```
  python3 tools/mylo_users.py add ali --days 30        # کاربر جدید (رمز خودکار ساخته می‌شود)
  python3 tools/mylo_users.py passwd ali
  python3 tools/mylo_users.py expire ali --days 60
  python3 tools/mylo_users.py remove ali
  python3 tools/mylo_users.py list
  ```
  خروجی در `dist/users.json` ساخته می‌شود. فایل `tools/users.private.json` (رمزها و اکانت VPN به‌صورت متن ساده) فقط روی کامپیوتر خودتان بماند.
- دو راه برای رساندن `users.json` به اپ:
  1. **سرور HTTPS** (پیشنهادی؛ حذف/تغییر کاربر بدون ساخت دوبارهٔ اپ): فایل را آپلود کنید و آدرس را در `Defaults.authURL` بگذارید. اپ هنگام باز شدن و هر چند ساعت یک‌بار چک می‌کند؛ کاربر حذف‌شده یا منقضی‌شده خارج می‌شود. آفلاین حداکثر ۷ روز مجاز است.
  2. **داخل خود اپ**: خروجی `python3 tools/mylo_users.py embed` را در `Defaults.embeddedUsers` بگذارید و اپ را دوباره بسازید. (نسخهٔ فعلی همین‌طور آمده و فقط کاربر `mehdi` را دارد.)
- پنج بار رمز غلط پشت‌سرهم باعث تأخیر موقت روی همان گوشی می‌شود.

## بیلد
1. Xcode 15+؛ iOS 16+. روش XcodeGen: `brew install xcodegen && xcodegen && open MYLO.xcodeproj`
   یا پروژهٔ iOS App (SwiftUI) بسازید، پوشهٔ `MYLO` را اضافه کنید (فایل @main پیش‌فرض را حذف کنید).
2. Build Settings: **Swift Language Version = Swift 5**؛ اگر گزینهٔ *Default Actor Isolation* دیدید روی **nonisolated** بگذارید.
3. Signing: Team و Bundle ID یکتا. روی گوشی واقعی اجرا کنید.

## دو حالت اتصال
- **با Personal VPN (اکانت پولی Apple Developer):** دکمهٔ پاور مستقیم وصل می‌شود (Signing & Capabilities ← + Capability ← Personal VPN).
- **بدون آن (Apple ID رایگان):** دکمهٔ پاور پروفایل VPN را نصب می‌کند (Safari ← Allow ← Settings ← Profile Downloaded ← Install) و VPN را از Settings ← VPN روشن می‌کنید. وضعیت، سرعت و آمار در اپ نمایش داده می‌شود. صفحهٔ Advanced وضعیت entitlement را نشان می‌دهد.

## تفاوت با اندروید
- بدون تقسیم ترافیک (Iran direct): iOS اجازهٔ route سفارشی نمی‌دهد؛ پینگ «Iran (direct)» فقط وقتی VPN خاموش است کار می‌کند.
- تغییر آیکن اپ، MTU، به‌روزرسانی APK و ایمپورت گواهی حذف شده‌اند (روی iOS معنی ندارند).
- Failover و آمار فقط وقتی اپ باز است کار می‌کند.


## وضعیت اتصال (Protected) - قانون‌ها
- فقط `VpnController.declareConnected(...)` اجازهٔ ست کردن `.connected` دارد. منبع معتبر فقط دو چیز است:
  1. `nativeStatus`: وضعیت `NEVPNManager` برای تونلی که خود اپ ساخته (حالت native).
  2. `routeProof`: (حالت profile) iOS ترافیک عادی اینترنت را واقعاً از یک interface تونل (`utun/ipsec/ppp`) بیرون می‌فرستد، در دو نمونهٔ پشت‌سرهم. تشخیص با `NetIf.defaultRouteInterface()` است (UDP connect بدون ارسال بسته، سپس منبع آدرس).
- این‌ها Protected نمی‌سازند: نصب پروفایل، وجود utun (حتی با IP)، دسترسی به اینترنت، موفق بودن ping/TCP.
- iOS برای اپ بدون entitlement هیچ API برای خواندن وضعیت پروفایلِ نصب‌شده از Settings ندارد؛ برای سخت‌گیری بیشتر `Defaults.profileAutoDetect = false` بگذارید تا حالت profile هرگز Protected نشان ندهد.
- محدودیت: route proof ثابت می‌کند «یک VPN ترافیک را می‌برد»، نه اینکه دقیقاً پروفایل MYLO است.

## ورود بدون نام کاربری/رمز
- `Defaults.requireLogin = false`. حساب IKEv2 را یک‌بار در Profile > Advanced وارد کنید (در Keychain می‌ماند) یا در `Defaults.vpnUser/vpnPass` بگذارید (داخل IPA قابل استخراج است).

## VLESS / VMess / Trojan / OpenVPN
- Profile > Add configuration: لینک، subscription (base64) یا فایل `.ovpn`. پارسر در `Data/ProxyConfig.swift`، اسرار در Keychain.
- اتصال هنوز وجود ندارد: نیاز به Network Extension (Packet Tunnel) + هستهٔ Xray/sing-box یا OpenVPN و حساب پولی Apple Developer دارد. `ConfigStore.singBoxJSON(for:)` کانفیگ آمادهٔ sing-box را می‌سازد.
