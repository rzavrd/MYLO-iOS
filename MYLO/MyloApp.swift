import SwiftUI
import UIKit

@main
struct MyloApp: App {
    @StateObject private var vm = VpnViewModel()
    @StateObject private var auth = AuthModel()

    init() {
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
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
