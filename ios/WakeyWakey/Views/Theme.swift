import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity,
        )
    }

    static let wwBackground = Color(hex: 0x101118)
    static let wwSurface = Color(hex: 0x1B1C26)
    static let wwSurface2 = Color(hex: 0x272935)
    static let wwBorder = Color.white.opacity(0.07)
    static let wwText = Color(hex: 0xF5F5F7)
    static let wwMuted = Color(hex: 0x9A9CAB)
    static let wwAccent = Color(hex: 0xA5B4FC)
    static let wwAccentLight = Color(hex: 0xB6C2FF)
    static let wwAccentSoft = Color(hex: 0xA5B4FC, opacity: 0.14)
    static let wwAccentText = Color(hex: 0x15162B)
    static let wwMoon = Color(hex: 0xF6D98B)
    static let wwGood = Color(hex: 0x6EE7A8)
    static let wwBad = Color(hex: 0xFF8A8A)
    static let wwNightText = Color(hex: 0x4A4A52)
}

extension Font {
    /// Rounded numerals and the logo, like SF Pro Rounded.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension ShapeStyle where Self == LinearGradient {
    static var wwPrimary: LinearGradient {
        LinearGradient(colors: [.wwAccentLight, .wwAccent], startPoint: .top, endPoint: .bottom)
    }
}

/// The app's card: a dark surface with a faint top sheen, hairline border and soft shadow.
struct CardBackground: ViewModifier {
    var glow: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.wwSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.035), .clear], startPoint: .top, endPoint: .center))
                    }
                    .overlay {
                        if let glow {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(RadialGradient(colors: [glow.opacity(0.13), .clear], center: .topLeading, startRadius: 0, endRadius: 260))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.wwBorder)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
            }
    }
}

extension View {
    func card(glow: Color? = nil) -> some View {
        modifier(CardBackground(glow: glow))
    }
}

/// The main button style: a periwinkle pill that presses in slightly.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.wwAccentText)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.wwPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .wwAccent.opacity(0.25), radius: 12, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.wwText)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.wwSurface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Cards and rows that press in slightly when tapped.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shared formatting.
enum Format {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    /// "+8 min" (early) or "−2h 18m" (late).
    static func signed(minutes: Int) -> String {
        if minutes == 0 { return "On time" }
        let abs = Swift.abs(minutes)
        let amount = abs < 60 ? "\(abs) min" : "\(abs / 60)h" + (abs % 60 == 0 ? "" : " \(abs % 60)m")
        return (minutes > 0 ? "+" : "−") + amount
    }

    static func relativeDay(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        return SleepSchedule.dayNames[SleepSchedule.dayIndex(of: date)]
    }

    static func historyDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
