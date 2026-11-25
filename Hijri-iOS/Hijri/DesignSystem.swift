import SwiftUI
import UIKit

enum HijriTheme: String, CaseIterable, Identifiable {
    case royal, emerald, minimal, lavender, sky
    case paper, aurora
    static let allCases: [HijriTheme] = [.royal, .emerald, .minimal, .lavender, .sky]
    var id: Self { self }
    var current: Self { self == .paper ? .minimal : self == .aurora ? .lavender : self }
    var title: String {
        switch current {
        case .royal: return tr("ملكي ليلي", "Royal Night")
        case .emerald: return tr("زمردي نباتي", "Botanical Emerald")
        case .minimal: return tr("مبسّط تحريري", "Editorial Minimal")
        case .lavender: return tr("شفق زجاجي", "Glass Twilight")
        default: return tr("سماء عائمة", "Floating Sky")
        }
    }
    var subtitle: String {
        switch current {
        case .royal: return tr("عجلتان منفصلتان وبطاقات مشطوفة", "Separate date wheels and cut-corner cards")
        case .emerald: return tr("المناسبة والموعد أولًا، ثم عجلتا التاريخ", "Events and appointments above the date wheels")
        case .minimal: return tr("تاريخان مختصران وإدخال تاريخ الميلاد", "Compact dates and birth-date entry")
        case .lavender: return tr("العجلتان داخل بطاقة واحدة", "Both date wheels in one card")
        default: return tr("شريط أسبوع وبطاقتا التاريخ جنبًا إلى جنب", "Week strip and side-by-side dates")
        }
    }
    var prefersDark: Bool { current == .royal || current == .lavender }
    var corner: CGFloat {
        switch current {
        case .royal: return 8
        case .emerald: return 20
        case .minimal: return 0
        case .lavender: return 24
        default: return 28
        }
    }
    var headerFont: Font { .system(size: 23, weight: .bold, design: current == .royal ? .serif : .default) }
    var accent: Color { ThemePalette(theme: current, dark: prefersDark).accent }
}

enum HijriAppearance: String, CaseIterable, Identifiable {
    case theme, system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .theme: return tr("حسب الثيم", "Follow theme")
        case .system: return tr("حسب إعداد الجهاز", "Follow device")
        case .light: return tr("فاتح", "Light")
        case .dark: return tr("داكن", "Dark")
        }
    }
    var colorScheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
}

private struct RGB {
    let r: Double
    let g: Double
    let b: Double
    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 255) / 255
        g = Double((hex >> 8) & 255) / 255
        b = Double(hex & 255) / 255
    }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    var color: Color { Color(red: r, green: g, blue: b) }
    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return linear(r) * 0.2126 + linear(g) * 0.7152 + linear(b) * 0.0722
    }
    func mixed(with other: RGB, fraction: Double) -> RGB {
        RGB(r: r + (other.r - r) * fraction, g: g + (other.g - g) * fraction, b: b + (other.b - b) * fraction)
    }
    func readable(on backgrounds: [RGB], minimum: Double = 7) -> RGB {
        func worst(_ color: RGB) -> Double {
            backgrounds.map { (max(color.luminance, $0.luminance) + 0.05) / (min(color.luminance, $0.luminance) + 0.05) }.min() ?? 1
        }
        guard worst(self) < minimum else { return self }
        let endpoint = worst(RGB(0)) >= worst(RGB(0xFFFFFF)) ? RGB(0) : RGB(0xFFFFFF)
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if worst(mixed(with: endpoint, fraction: middle)) >= minimum { high = middle } else { low = middle }
        }
        return mixed(with: endpoint, fraction: high)
    }
}

struct ThemePalette {
    let theme: HijriTheme
    let background: Color
    let card: Color
    let ink: Color
    let accent: Color
    let selected: Color
    let onAccent: Color
    let outline: Color
    init(theme: HijriTheme, dark: Bool) {
        self.theme = theme.current
        let shades: [UInt32]
        switch (theme.current, dark) {
        case (.royal, true): shades = [0x0C1426,0x172440,0xFFF4DB,0xE9C887,0x302B31]
        case (.royal, false): shades = [0xF2F3F8,0xFFFCF6,0x202943,0x775819,0xF1E2C3]
        case (.emerald, true): shades = [0x0E2119,0x162D23,0xEBFAEF,0xABE3BA,0x234937]
        case (.emerald, false): shades = [0xEFF6ED,0xFBFFF8,0x142C23,0x226048,0xD8EBDB]
        case (.minimal, true): shades = [0x151515,0x202020,0xF1F0ED,0xE5E2DF,0x343332]
        case (.minimal, false): shades = [0xF5F3EF,0xFAF9F6,0x1C1C1D,0x202023,0xE7E3DE]
        case (.lavender, true): shades = [0x1E2730,0x2C353F,0xF4F2F8,0xD5C0F3,0x514369]
        case (.lavender, false): shades = [0xF5EEFF,0xFCF8FF,0x29203D,0x5D368F,0xEADCFB]
        case (_, true): shades = [0x101E38,0x192D4A,0xEBF4FF,0xB0D6FF,0x273E62]
        default: shades = [0xEDF5FF,0xFBFDFF,0x1B315A,0x2457A1,0xDBEAFF]
        }
        let bg = RGB(shades[0]), surface = RGB(shades[1]), selection = RGB(shades[4])
        let surfaces = [bg, surface, selection]
        let text = RGB(shades[2]).readable(on: surfaces)
        let primary = RGB(shades[3]).readable(on: surfaces)
        background = bg.color
        card = surface.color
        ink = text.color
        accent = primary.color
        selected = selection.color
        onAccent = (dark ? bg : RGB(0xFFFFFF)).readable(on: [primary]).color
        outline = text.readable(on: surfaces, minimum: 3.05).color.opacity(0.65)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette(theme: .lavender, dark: true)
}
extension EnvironmentValues {
    var hijriPalette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

struct DesignRootStyle: ViewModifier {
    @AppStorage("designTheme") private var theme = HijriTheme.lavender
    @AppStorage("appearance") private var appearance = HijriAppearance.theme
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = appearance == .theme ? theme.prefersDark : appearance == .dark || (appearance == .system && scheme == .dark)
        let palette = ThemePalette(theme: theme, dark: dark)
        typography(content).environment(\.hijriPalette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            .preferredColorScheme(appearance == .theme ? (theme.prefersDark ? .dark : .light) : appearance.colorScheme)
    }
    @ViewBuilder private func typography(_ content: Content) -> some View {
        if #available(iOS 16.1, *) { content.fontDesign(theme.current == .royal ? .serif : .default) }
        else { content }
    }

}

struct DesignShape: InsettableShape {
    var theme: HijriTheme
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard theme.current == .royal else {
            return Path(roundedRect: rect, cornerRadius: max(0, theme.corner - insetAmount))
        }
        let cut = max(0, min(8 - insetAmount, rect.width / 2, rect.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
    func inset(by amount: CGFloat) -> DesignShape {
        var result = self
        result.insetAmount += amount
        return result
    }
}

struct DesignCard<Content: View>: View {
    @Environment(\.hijriPalette) private var palette
    var selected = false
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        let shape = DesignShape(theme: palette.theme)
        VStack(alignment: .leading, spacing: 0) {
            if palette.theme == .minimal { palette.accent.frame(height: 2) }
            if palette.theme == .royal { palette.accent.opacity(0.45).frame(height: 1).padding(.horizontal, 12) }
            content.padding(padding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.selected : palette.card, in: shape)
        .overlay(shape.strokeBorder(palette.theme == .royal ? palette.accent : palette.outline,
                                    lineWidth: palette.theme == .royal ? 1.2 : palette.theme == .minimal ? 1 : 0))
        .shadow(color: .black.opacity(palette.theme == .lavender || palette.theme == .sky ? 0.14 : 0), radius: 3, y: 2)
    }
}

struct DesignBackground: View {
    @Environment(\.hijriPalette) private var palette
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                palette.background
                if palette.theme == .royal {
                    LinearGradient(colors: [Color.blue.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom)
                    DesignShape(theme: .royal).stroke(palette.accent.opacity(0.18), lineWidth: 1).padding(8)
                }
                if palette.theme == .emerald || palette.theme == .sky {
                    LinearGradient(colors: [.clear, palette.selected.opacity(0.56)], startPoint: .top, endPoint: .bottom)
                    ForEach(0..<3) { index in
                        Circle().stroke(palette.accent.opacity(0.12), lineWidth: 1)
                            .frame(width: geometry.size.width * (0.7 + Double(index) * 0.18))
                            .position(x: geometry.size.width * 0.94, y: geometry.size.height * 0.085)
                    }
                }
            }
        }.ignoresSafeArea()
    }
}

struct DesignPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !title.isEmpty { Text(title).font(.title2.bold()).padding(.vertical, 5).accessibilityAddTraits(.isHeader) }
                content
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .background { DesignBackground() }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct RaisedButtonStyle: ButtonStyle {
    @Environment(\.hijriPalette) private var palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold())
            .padding(.horizontal, 24).padding(.vertical, 10)
            .foregroundStyle(palette.onAccent)
            .background(LinearGradient(colors: [palette.accent.opacity(0.85), palette.accent], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.38), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}
