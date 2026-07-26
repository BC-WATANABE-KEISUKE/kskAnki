import SwiftUI

/// アプリ全体のテーマ＆カラーヘルパー (UX-14: themeColorHex 反映 & RFC-08: カラー共通定義一元化)
public extension Color {
    init(hex: String) {
        let hexCleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexCleaned).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hexCleaned.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // RFC-08: 背景色・カード背景色の共通色定義 (重復コード排除)
    static var appBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color.gray.opacity(0.05)
        #endif
    }
    
    static var cardBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }
    
    static var frontCardBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        return Color.gray.opacity(0.08)
        #endif
    }
}
