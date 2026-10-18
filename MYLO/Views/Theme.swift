import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

struct Palette {
    let name: String
    let dark: Bool
    let bg, card, ink, muted, accent, idle, glow, bar, barSel, track: Color
}

enum Palettes {
    static let twilight = Palette(name: "Twilight", dark: true, bg: Color(hex: 0x050F18), card: Color(hex: 0x111F2C), ink: .white, muted: Color(hex: 0x8FA3B5),
        accent: Color(hex: 0x4DB89C), idle: Color(hex: 0x4DB89C), glow: Color(hex: 0x123F3C), bar: Color(hex: 0x16293A), barSel: Color(hex: 0x0A1B2C), track: Color(hex: 0xCDD3D8))
    static let midnight = Palette(name: "Midnight", dark: true, bg: Color(hex: 0x061523), card: Color(hex: 0x12263A), ink: .white, muted: Color(hex: 0x8FA3B5),
        accent: Color(hex: 0xC6E03F), idle: Color(hex: 0xC6E03F), glow: Color(hex: 0x6FA43E), bar: Color(hex: 0x16293C), barSel: Color(hex: 0x0A1B2C), track: Color(hex: 0xCDD3D8))
    static let sand = Palette(name: "Sand", dark: false, bg: Color(hex: 0xF7F6F1), card: .white, ink: Color(hex: 0x14202B), muted: Color(hex: 0x6B7A86),
        accent: Color(hex: 0x2E9E6B), idle: Color(hex: 0x2E9E6B), glow: Color(hex: 0xC9DC3A), bar: Color(hex: 0xEDECE5), barSel: .white, track: Color(hex: 0xD5D9DC))
    static let sky = Palette(name: "Sky", dark: false, bg: Color(hex: 0xF3F6F5), card: .white, ink: Color(hex: 0x14202B), muted: Color(hex: 0x66777F),
        accent: Color(hex: 0x2F8F83), idle: Color(hex: 0x2F8F83), glow: Color(hex: 0x9CCBC5), bar: Color(hex: 0xE8EFEE), barSel: .white, track: Color(hex: 0xD5DCDC))
    static let autumn = Palette(name: "Autumn", dark: false, bg: Color(hex: 0xF7F6F1), card: .white, ink: Color(hex: 0x14202B), muted: Color(hex: 0x6B7A86),
        accent: Color(hex: 0x3F9A5A), idle: Color(hex: 0x3F9A5A), glow: Color(hex: 0x86B84F), bar: Color(hex: 0xEDECE5), barSel: .white, track: Color(hex: 0xD5D9DC))
    static let white = Palette(name: "White", dark: false, bg: .white, card: Color(hex: 0xF2F4F6), ink: Color(hex: 0x101820), muted: Color(hex: 0x66737F),
        accent: Color(hex: 0x1FA37A), idle: Color(hex: 0x1FA37A), glow: Color(hex: 0xBFE8DA), bar: Color(hex: 0xEEF0F3), barSel: .white, track: Color(hex: 0xD8DDE2))

    static let names = ["System", "White", "Sand", "Midnight", "Sky", "Twilight", "Autumn"]

    static func byName(_ n: String, systemDark: Bool) -> Palette {
        switch n {
        case "White": return white
        case "Sand": return sand
        case "Midnight": return midnight
        case "Sky": return sky
        case "Twilight": return twilight
        case "Autumn": return autumn
        default: return systemDark ? twilight : sand
        }
    }
}

/// Current palette. The root view is re-created when it changes (see AppRoot), so every view just reads `C`.
final class Pal: ObservableObject {
    static let shared = Pal()
    @Published var cur = Palettes.twilight
}

enum C {
    static var bg: Color { Pal.shared.cur.bg }
    static var card: Color { Pal.shared.cur.card }
    static var ink: Color { Pal.shared.cur.ink }
    static var muted: Color { Pal.shared.cur.muted }
    static var teal: Color { Pal.shared.cur.accent }
    static var pink: Color { Pal.shared.cur.idle }
    static var glow: Color { Pal.shared.cur.glow }
    static var track: Color { Pal.shared.cur.track }
    static var barBg: Color { Pal.shared.cur.bar }
    static var barSel: Color { Pal.shared.cur.barSel }
    static let danger = Color(hex: 0xE5484D)
    static let mapBg = Color(hex: 0x172230)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card(_ padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
    func screenBg() -> some View { background(C.bg.ignoresSafeArea()) }
}

/// Polyline arc (degrees, 0 = right, increasing clockwise on screen). Robust against addArc direction quirks.
func arcPath(center: CGPoint, radius: CGFloat, from a: Double, to b: Double) -> Path {
    var p = Path()
    if b <= a { return p }
    var d = a
    p.move(to: CGPoint(x: center.x + radius * CGFloat(cos(d * .pi / 180)), y: center.y + radius * CGFloat(sin(d * .pi / 180))))
    while d < b {
        d = min(d + 2, b)
        p.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(d * .pi / 180)), y: center.y + radius * CGFloat(sin(d * .pi / 180))))
    }
    return p
}

// MARK: - shared building blocks

struct SubHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    let trailing: Trailing

    init(_ title: String, onBack: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.onBack = onBack; self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left").font(.mylo(18, weight: .semibold)).foregroundColor(C.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(C.barBg))
            }
            Spacer()
            Text(title).font(.mylo(20, weight: .bold)).foregroundColor(C.ink)
            Spacer()
            trailing.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

extension SubHeader where Trailing == EmptyView {
    init(_ title: String, onBack: @escaping () -> Void) {
        self.init(title, onBack: onBack) { EmptyView() }
    }
}

struct SectionTitle: View {
    let t: String
    init(_ t: String) { self.t = t }
    var body: some View {
        Text(t).font(.mylo(14)).foregroundColor(C.muted)
            .padding(.leading, 20).padding(.top, 22).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var chevron: Bool = false
    let trailing: Trailing

    init(icon: String, title: String, subtitle: String? = nil, value: String? = nil, chevron: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.value = value
        self.chevron = chevron; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.mylo(20)).foregroundColor(C.ink).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.mylo(18)).foregroundColor(C.ink)
                if let subtitle { Text(subtitle).font(.mylo(13)).foregroundColor(C.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(.mylo(15)).foregroundColor(C.ink) }
            trailing
            if chevron { Image(systemName: "chevron.right").foregroundColor(C.ink) }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

extension SettingRow where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, value: String? = nil, chevron: Bool = false) {
        self.init(icon: icon, title: title, subtitle: subtitle, value: value, chevron: chevron) { EmptyView() }
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(icon: icon, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn).labelsHidden().tint(C.teal)
        }
    }
}

struct Segmented: View {
    let options: [String]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Button { selected = i } label: {
                    Text(o).fontWeight(.semibold).foregroundColor(i == selected ? C.teal : C.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 20).fill(i == selected ? C.track.opacity(Pal.shared.cur.dark ? 0.35 : 0.9) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 24).fill(C.barBg))
        .padding(.horizontal, 20)
    }
}

struct SignalBars: View {
    let level: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < level ? C.teal : C.muted.opacity(0.35))
                    .frame(width: 4, height: 16 * (0.4 + 0.3 * CGFloat(i)))
            }
        }
        .frame(width: 18, height: 16, alignment: .bottom)
    }
}


extension View {
    /// `onChange` without the iOS 17 deprecation warning, still working on iOS 16.
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.onChange(of: value) { _, new in action(new) }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}


extension Font {
    /// System font that follows the phone's text size (Settings > Display & Brightness > Text Size, and the
    /// Control Center slider). Growth is capped at 1.3x so the fixed-size cards and the tab bar stay usable.
    static func mylo(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
#if canImport(UIKit)
        let scaled = min(UIFontMetrics.default.scaledValue(for: size), size * 1.3)
#else
        let scaled = size
#endif
        return .system(size: scaled, weight: weight, design: design)
    }
}
