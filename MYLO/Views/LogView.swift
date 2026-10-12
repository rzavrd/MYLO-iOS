import UIKit
import SwiftUI

struct LogView: View {
    @EnvironmentObject var vm: VpnViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.lines.isEmpty { Text("Nothing yet.").foregroundColor(C.muted) }
            else {
                HStack {
                    Spacer()
                    ShareLink(item: vm.lines.joined(separator: "\n")) {
                        Label("Share", systemImage: "square.and.arrow.up").foregroundColor(C.teal)
                    }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.lines.reversed().enumerated()), id: \.offset) { _, l in
                        Text(l).font(.mylo(11, design: .monospaced)).foregroundColor(C.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
    }
}
