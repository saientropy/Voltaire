import SwiftUI

enum ReadingTokens {
    static let canvas = Color(red: 0.96, green: 0.94, blue: 0.88)
    static let ink = Color(red: 0.12, green: 0.11, blue: 0.09)
    static let secondaryInk = Color(red: 0.35, green: 0.33, blue: 0.28)
    static let controlSurface = Color(red: 0.985, green: 0.972, blue: 0.93)
    static let hairline = ink.opacity(0.14)
    static let pagePadding: CGFloat = 48
    static let libraryPadding: CGFloat = 32
    static let libraryMaxWidth: CGFloat = 1180
    static let touchTarget: CGFloat = 48
    static let cardCornerRadius: CGFloat = 20
    static let lineSpacing: CGFloat = 9
}
