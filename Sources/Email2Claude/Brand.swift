import AppKit
import SwiftUI

/// eMail to Claude brand colors. See BRAND.md for usage guidance.
enum Brand {
    static let navy = Color(hex: 0x0D47A1)       // primary; app icon background
    static let skyBlue = Color(hex: 0x42A5F5)    // active / accent on dark surfaces
    static let aliceBlue = Color(hex: 0xE3F2FD)  // light card backgrounds, secondary accents
    static let slate = Color(hex: 0x1E1E1E)      // primary text (alt 0F172A)
    static let coolGray = Color(hex: 0xE2E8F0)   // borders and dividers (alt F8FAFC)

    /// Navy on light surfaces, sky blue on dark ones, where plain navy would be hard to read.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(hex: 0x42A5F5) : NSColor(hex: 0x0D47A1)
    })
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}
