import SwiftUI

/// Design tokens for Pact — a dark, glassy "prediction-market" look (deep
/// indigo→violet→blue gradient, frosted translucent cards, bold white
/// numerals, a live-data feel) carrying Y2K DNA through its holographic
/// gradient and saturated accent palette rather than through bubble-arcade
/// chrome. Everything here is a token; screens should never hardcode a hex
/// or a font size directly.
enum Theme {

    enum Surface {
        /// The deep gradient every screen sits on.
        static let bg = LinearGradient(
            colors: [Color(hex: 0x120B2E), Color(hex: 0x271457), Color(hex: 0x2A3FA5)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        /// Flat fallback (status bar scrims, etc.) — the gradient's midpoint.
        static let bgFlat = Color(hex: 0x1D1140)
        /// Glass card fill — layered over the gradient with a blur material.
        static let glass = Color.white.opacity(0.08)
        static let glassBright = Color.white.opacity(0.14)
        static let border = Color.white.opacity(0.14)
        static let border2 = Color.white.opacity(0.22)
    }

    enum Ink {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.72)
        static let tertiary = Color.white.opacity(0.48)
        static let onBrand = Color.white
    }

    enum Brand {
        static let purple = Color(hex: 0x8B5CF6)
        static let purpleDeep = Color(hex: 0x4C1D95)
        static let blue = Color(hex: 0x3B82F6)
        static let pink = Color(hex: 0xF472B6)
        static let cyan = Color(hex: 0x22D3EE)
        static let lime = Color(hex: 0x84CC16)
        static let gold = Color(hex: 0xFBBF24)
        static let coral = Color(hex: 0xFB7185)

        /// Fixed cycle used to color-tag members and challenges — no avatar
        /// generation, just a deterministic swatch per identity.
        static let swatch: [Color] = [purple, pink, cyan, gold, lime, blue, coral]

        static let holo = LinearGradient(
            colors: [purple, blue, cyan, pink],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    enum Status {
        static let win = Brand.lime
        static let warn = Brand.gold
        static let danger = Brand.coral
    }

    enum Font {
        static func display(_ size: CGFloat = 34) -> SwiftUI.Font {
            .system(size: size, weight: .black, design: .rounded)
        }
        static func h1() -> SwiftUI.Font { .system(size: 26, weight: .bold, design: .rounded) }
        static func h2() -> SwiftUI.Font { .system(size: 19, weight: .bold, design: .rounded) }
        static func h3() -> SwiftUI.Font { .system(size: 16, weight: .semibold, design: .rounded) }
        static func number(_ size: CGFloat = 22) -> SwiftUI.Font {
            .system(size: size, weight: .black, design: .rounded)
        }
        static func body() -> SwiftUI.Font { .system(size: 15, weight: .medium, design: .rounded) }
        static func caption() -> SwiftUI.Font { .system(size: 13, weight: .medium, design: .rounded) }
        static func eyebrow() -> SwiftUI.Font { .system(size: 11, weight: .bold, design: .rounded) }
        static func button() -> SwiftUI.Font { .system(size: 16, weight: .bold, design: .rounded) }
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 36
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let card: CGFloat = 24
        static let pill: CGFloat = 999
    }

    enum Motion {
        static let pop = Animation.spring(response: 0.34, dampingFraction: 0.62)
        static let settle = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let fade = Animation.easeOut(duration: 0.28)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
