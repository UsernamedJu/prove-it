import SwiftUI
import UIKit

/// Design tokens for Pact 2.0 — a light, high-contrast base built for
/// legibility (big type, flat white cards, soft shadows — no glass-blur on
/// standard surfaces, since thin frosted borders are hard to read for older
/// eyes) with two reserved "hero" moments (challenge photos, onboarding)
/// where a warm dark scrim + real frosted glass carries the excitement.
/// Everything here is a token; screens should never hardcode a hex or a
/// font size directly.
enum Theme {

    enum Surface {
        /// Warm paper base every screen sits on — flat, not a gradient.
        /// Dynamic: resolves dark in Dark Mode (Settings → Appearance).
        static let bg = Color.dynamic(light: 0xF7F4EE, dark: 0x121214)
        static let bgFlat = Color.dynamic(light: 0xF7F4EE, dark: 0x121214)
        /// Card fill — solid, not a blur material. Legible first.
        static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1E1E21)
        static let glass = Color.dynamic(light: 0x000000, dark: 0xFFFFFF).opacity(0.035)
        static let glassBright = Color.dynamic(light: 0x000000, dark: 0xFFFFFF).opacity(0.06)
        static let border = Color.dynamic(light: 0x000000, dark: 0xFFFFFF).opacity(0.08)
        static let border2 = Color.dynamic(light: 0x000000, dark: 0xFFFFFF).opacity(0.14)
        /// The dark scrim laid over a hero photo (challenge detail, hero cards)
        /// — unchanged across modes on purpose, since it sits on a photo, not
        /// the page background.
        static let heroScrimTop = Color.black.opacity(0.05)
        static let heroScrimBottom = Color.black.opacity(0.68)
    }

    enum Ink {
        static let primary = Color.dynamic(light: 0x18181B, dark: 0xF2F2F4)
        static let secondary = Color.dynamic(light: 0x5C5C63, dark: 0xB8B8BE)
        static let tertiary = Color.dynamic(light: 0x96969C, dark: 0x86868C)
        /// Text/icons on a filled accent surface (buttons) or a photo hero —
        /// unchanged across modes; it's never sitting directly on `Surface.bg`.
        static let onBrand = Color.white
    }

    enum Brand {
        // Every call site references these by name, so only the values
        // moved — "purple" is now the app's primary lime, "cyan" is now the
        // near-black structural ink used for the tab bar and dark chrome.
        static let purple = Color(hex: 0x7CB518)     // Primary — lime, CTAs & active states
        static let purpleDeep = Color(hex: 0x527A0E) // Deep lime — pressed/gradient shade
        static let blue = Color(hex: 0x3AA6D9)        // Sky — secondary data accent
        static let pink = Color(hex: 0xFF5C77)        // Coral — competitive/energy accent
        static let cyan = Color.dynamic(light: 0x1A1A1D, dark: 0x2C2C30) // Ink black — structural chrome (tab bar, dark buttons); lighter in Dark Mode so it still reads as a distinct surface against an even-darker page
        static let lime = Color(hex: 0x2FA84F)        // Win green — distinct from primary, "ahead/won"
        static let gold = Color(hex: 0xFBBF24)        // Unchanged — reward/streak
        static let coral = Color(hex: 0x9C97A3)       // Muted slate — "loss/behind", desaturated on purpose

        /// Fixed cycle used to color-tag members and challenges — no avatar
        /// generation, just a deterministic swatch per identity.
        static let swatch: [Color] = [purple, pink, blue, gold, lime, cyan, coral]

        static let holo = LinearGradient(
            colors: [purple, gold, pink],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// A spread of greens (yellow-green → mint → forest → deep teal-green)
        /// for onboarding/settings body-profile sliders — a "rainbow" that
        /// stays inside the green family, distinct from `holo`'s purple/gold/pink.
        static let greenHolo = LinearGradient(
            colors: [Color(hex: 0xA3E635), Color(hex: 0x4ADE80), Color(hex: 0x16A34A), Color(hex: 0x065F46)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    enum Status {
        static let win = Brand.lime
        static let warn = Brand.gold
        static let danger = Brand.coral
    }

    enum Font {
        static func display(_ size: CGFloat = 36) -> SwiftUI.Font {
            .system(size: size, weight: .black, design: .rounded)
        }
        static func h1() -> SwiftUI.Font { .system(size: 28, weight: .bold, design: .rounded) }
        static func h2() -> SwiftUI.Font { .system(size: 20, weight: .bold, design: .rounded) }
        static func h3() -> SwiftUI.Font { .system(size: 17, weight: .semibold, design: .rounded) }
        static func number(_ size: CGFloat = 22) -> SwiftUI.Font {
            .system(size: size, weight: .black, design: .rounded)
        }
        static func body() -> SwiftUI.Font { .system(size: 16, weight: .medium, design: .rounded) }
        static func caption() -> SwiftUI.Font { .system(size: 14, weight: .medium, design: .rounded) }
        static func eyebrow() -> SwiftUI.Font { .system(size: 12, weight: .bold, design: .rounded) }
        static func button() -> SwiftUI.Font { .system(size: 17, weight: .bold, design: .rounded) }
        /// The "Provyr" wordmark — a plain (not rounded) bold sans, paired
        /// with tight tracking. The rounded/black `display()` face reads as
        /// playful and works for stat numbers, but felt too bubbly/childish
        /// as the actual logotype; this is the more grown-up alternative.
        static func wordmark(_ size: CGFloat = 32) -> SwiftUI.Font { .system(size: size, weight: .bold, design: .default) }
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
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 22
        static let card: CGFloat = 26
        static let pill: CGFloat = 999
    }

    enum Motion {
        static let pop = Animation.spring(response: 0.34, dampingFraction: 0.62)
        static let settle = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let fade = Animation.easeOut(duration: 0.28)
        /// Lateral slides — onboarding/flow steps and the main tab bar.
        /// A snappy, near-critically-damped spring reads as fluid iOS motion
        /// without the visible overshoot of `pop`, which is reserved for
        /// in-place UI feedback (taps, selection, toggles), not navigation.
        static let push = Animation.spring(response: 0.34, dampingFraction: 0.86)
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

    /// Resolves to a different hex depending on the *current* trait
    /// environment instead of being fixed at declaration time — what lets
    /// a whole palette of `static let` tokens support Dark Mode without
    /// turning every one of them into a view-scoped computed property.
    /// `.preferredColorScheme(_:)` (set from `AppearancePreference` in
    /// Settings) is what actually drives which branch resolves.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}
