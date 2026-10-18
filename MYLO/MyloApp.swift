import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct MyloApp: App {
    @StateObject private var vm = VpnViewModel()
    @StateObject private var auth = AuthModel()

    init() {
#if canImport(UIKit)
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
#elseif canImport(AppKit)
        let appearanceName = NSAppearance.current.name.rawValue
        let dark = appearanceName.contains("dark")
#endif
        Pal.shared.cur = Palettes.byName(Store.shared.theme, systemDark: dark)
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(vm)
                .environmentObject(auth)
                .onOpenURL { url in if url.isFileURL { vm.openOvpnFile(url) } }   // .ovpn file opened with MYLO; mylo://done (Shortcuts) is ignored
        }
    }
}
