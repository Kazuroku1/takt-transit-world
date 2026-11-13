import SwiftUI

enum TaktTheme {
    static let background = Color(hex: 0xF6F6F0)
    static let paper = Color(hex: 0xFFFEF7)
    static let ink = Color(hex: 0x344B3B)
    static let muted = Color(hex: 0x7C8B70)
    static let green = Color(hex: 0x4D6F4B)
    static let coral = Color(hex: 0xE88660)
    static let border = Color(hex: 0xE2E8D8)
    static let pale = Color(hex: 0xEAF0E0)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

struct Eyebrow: View {
    let text: String
    var color = TaktTheme.muted
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.5).foregroundStyle(color)
    }
}
struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(19).background(TaktTheme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(TaktTheme.border, lineWidth: 1))
    }
}
struct TaktButtonStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded, weight: .semibold))
            .frame(minHeight: 46).frame(maxWidth: .infinity)
            .foregroundStyle(secondary ? TaktTheme.green : .white)
            .background(secondary ? TaktTheme.pale : TaktTheme.green, in: RoundedRectangle(cornerRadius: 13))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
struct SoftIcon: View {
    let name: String
    var color = TaktTheme.green
    var body: some View {
        Image(systemName: name).font(.system(size: 21, weight: .medium))
            .foregroundStyle(color).frame(width: 44, height: 46)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
    }
}
