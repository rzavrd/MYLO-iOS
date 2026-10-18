#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI

struct StatsView: View {
    @EnvironmentObject var vm: VpnViewModel
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, HH:mm"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        let ss = vm.stats
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Statistics").font(.mylo(24, weight: .bold)).foregroundColor(C.ink).padding(.top, 12)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("Live").foregroundColor(C.muted)
                        Text("Down \(fmtBits(ss.downBps))").font(.mylo(13)).foregroundColor(C.teal)
                        Text("Up \(fmtBits(ss.upBps))").font(.mylo(13)).foregroundColor(C.pink)
                    }
                    Canvas { ctx, size in
                        series(&ctx, size, ss.downHist, C.teal)
                        series(&ctx, size, ss.upHist, C.pink)
                    }
                    .frame(height: 110)
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Data used").foregroundColor(C.muted)
                    ForEach([("Today", 1), ("Last 7 days", 7), ("Last 30 days", 30)], id: \.0) { label, days in
                        let u = vm.store.usage(days: days)
                        HStack {
                            Text(label).foregroundColor(C.ink); Spacer()
                            Text("down \(fmtBytes(u.rx))  up \(fmtBytes(u.tx))").font(.mylo(13)).foregroundColor(C.muted)
                        }
                    }
                }
                .card()
                .id(ss.rx / 100_000 + ss.tx / 100_000)   // refresh as traffic accumulates

                Text("Connection history").foregroundColor(C.muted).padding(.top, 4)
                if vm.history.isEmpty { Text("No connections yet.").font(.mylo(13)).foregroundColor(C.muted) }
                ForEach(vm.history) { h in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(flagEmoji(h.cc))  \(h.server)").fontWeight(.semibold).foregroundColor(C.ink).lineLimit(1)
                            Text("\(Self.df.string(from: Date(timeIntervalSince1970: h.start))) - \(h.status)")
                                .font(.mylo(12)).foregroundColor(C.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(fmtDur(max(Int(h.end - h.start), 0))).font(.mylo(14)).foregroundColor(C.ink)
                            Text(fmtBytes(h.rx + h.tx)).font(.mylo(12)).foregroundColor(C.muted)
                        }
                    }
                    .padding(14)
                    .background(C.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Spacer().frame(height: 12)
            }
            .padding(.horizontal, 20)
        }
        .onAppear { vm.refreshHistory() }
    }

    private func series(_ ctx: inout GraphicsContext, _ size: CGSize, _ values: [Int64], _ color: Color) {
        guard values.count >= 2 else { return }
        let maxV = CGFloat(max(values.max() ?? 1, 1))
        var path = Path()
        for (i, v) in values.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = size.height - (CGFloat(v) / maxV) * size.height * 0.95
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(path, with: .color(color), lineWidth: 2)
    }
}
