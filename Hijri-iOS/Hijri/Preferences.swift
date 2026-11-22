import SwiftUI
import UIKit

enum HijriTheme: String, CaseIterable, Identifiable {
    case emerald, royal, paper, aurora, minimal

    var id: Self { self }

    var title: String {
        switch self {
        case .emerald: return "زمردي"
        case .royal: return "ملكي"
        case .paper: return "ورقي"
        case .aurora: return "عصري"
        case .minimal: return "مبسّط"
        }
    }

    var accent: Color {
        switch self {
        case .emerald: return .teal
        case .royal: return .purple
        case .paper: return .brown
        case .aurora: return .indigo
        case .minimal: return .blue
        }
    }

    var headerFont: Font {
        switch self {
        case .royal: return .system(.title2, design: .serif, weight: .bold)
        case .paper: return .system(.title2, design: .serif, weight: .medium)
        case .aurora: return .system(.title2, design: .rounded, weight: .bold)
        case .emerald, .minimal: return .title2.bold()
        }
    }
}

enum HijriAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: return "حسب إعداد الجهاز"
        case .light: return "فاتح"
        case .dark: return "داكن"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct PreferencesScreen: View {
    @AppStorage("appearance") private var appearance = HijriAppearance.system
    @AppStorage("designTheme") private var theme = HijriTheme.royal
    @AppStorage("numberSize") private var numberSize = 22.0
    @AppStorage("navigationTop") private var navigationTop = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("التصميم") {
                    Picker("الثيم", selection: $theme) {
                        ForEach(HijriTheme.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("المظهر", selection: $appearance) {
                        ForEach(HijriAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("التنقل أعلى الشاشة", isOn: $navigationTop)
                }
                Section("حجم الأرقام") {
                    Slider(value: $numberSize, in: 18...26, step: 1) {
                        Text("حجم الأرقام")
                    }
                    Text(Int(numberSize).formatted())
                        .font(.system(size: numberSize, weight: .semibold))
                    Button("الحجم الافتراضي") { numberSize = 22 }
                }
                Section("الأذونات") {
                    Button("إعدادات تطبيق هجري") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section("الويدجت") {
                    Text("من الشاشة الرئيسية، اضغط مطولًا ثم اختر إضافة أداة وابحث عن هجري.")
                }
            }
            .navigationTitle("الإعدادات")
        }
    }
}
