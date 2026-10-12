import UIKit
import SwiftUI

struct AssistantView: View {
    var onBack: () -> Void
    private let checks = deviceChecks()

    var body: some View {
        VStack(spacing: 0) {
            SubHeader("Secure Device Assistant", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Check your device is fully protected:").font(.mylo(22, weight: .bold)).foregroundColor(C.ink)
                        .padding(.vertical, 10)
                    ForEach(0..<checks.count, id: \.self) { i in
                        let c = checks[i]
                        VStack(alignment: .leading, spacing: 0) {
                            checkRow(c.title, c.desc, c.ok, 26)
                            if let d = c.detail {
                                Text(d).font(.mylo(14, weight: .semibold)).foregroundColor(C.ink).padding(.leading, 42).padding(.top, 8)
                            }
                            if let st = c.subTitle {
                                Rectangle().fill(C.muted.opacity(0.4)).frame(height: 1).padding(.leading, 42).padding(.vertical, 14)
                                checkRow(st, c.subDesc ?? "", c.subOk, 22).padding(.leading, 42)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(C.card).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    Spacer().frame(height: 12)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func checkRow(_ title: String, _ desc: String, _ ok: Bool, _ icon: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.mylo(icon)).foregroundColor(ok ? C.teal : C.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.mylo(19)).foregroundColor(C.ink)
                Text(desc).font(.mylo(14)).foregroundColor(C.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
