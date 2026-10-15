import SwiftUI

/// Luna, the streak mascot: a little moon drawn in the real moon phase. Her mood follows
/// the streak: asleep with no streak, smiling while one is going, and glowing with
/// sparkles once it reaches a week.
struct LunaView: View {
    enum Mood { case sleepy, happy, glowing }

    var streak: Int
    var size: CGFloat
    /// Fixed phase (0 new … 0.5 full), e.g. for the logo; nil follows the real moon.
    var phase: Double?
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bobbing = false

    private var mood: Mood {
        streak == 0 ? .sleepy : streak >= 7 ? .glowing : .happy
    }

    var body: some View {
        Canvas { context, canvasSize in
            draw(in: &context, size: canvasSize)
        }
        .frame(width: size, height: size)
        .shadow(color: mood == .sleepy ? .clear : .wwMoon.opacity(mood == .glowing ? 0.75 : 0.45), radius: mood == .glowing ? 16 : 9)
        .offset(y: bobbing ? -size * 0.04 : 0)
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: mood == .sleepy ? 2.5 : 1.6).repeatForever(autoreverses: true)) {
                bobbing = true
            }
        }
        .accessibilityLabel("Luna, \(MoonPhase.name(phase ?? MoonPhase.current()).lowercased())")
    }

    private func draw(in context: inout GraphicsContext, size canvasSize: CGSize) {
        let scale = canvasSize.width / 64
        context.scaleBy(x: scale, y: scale)
        let center = CGPoint(x: 32, y: 32), r: CGFloat = 25
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        let sleepy = mood == .sleepy
        let (light, dark, crater): (Color, Color, Color) = sleepy
            ? (Color(hex: 0xE4E5EE), Color(hex: 0xA9ABBD), Color(hex: 0x9497A8))
            : (Color(hex: 0xFFF6D6), Color(hex: 0xF3CF7A), Color(hex: 0xE2B55A))

        // The moon in shadow, faintly lit by earthshine so Luna is always visible.
        context.fill(disc, with: .color(Color(hex: 0x2D2F42)))
        context.stroke(disc, with: .color(.white.opacity(0.14)), lineWidth: 1)
        let face = facePath(sleepy: sleepy)
        let faceStyle = StrokeStyle(lineWidth: 2.4, lineCap: .round)
        context.stroke(face, with: .color(Color(hex: 0x8D90AD)), style: faceStyle)

        // The sunlit part, with craters, cheeks and face clipped to it.
        var lit = context
        lit.clip(to: MoonPhase.litPath(phase: phase ?? MoonPhase.current(), center: center, radius: r))
        lit.fill(disc, with: .radialGradient(Gradient(colors: [light, dark]), center: CGPoint(x: 24, y: 20), startRadius: 0, endRadius: 46))
        for (x, y, cr) in [(19.0, 20.0, 3.6), (46.0, 21.0, 2.2), (43.0, 49.0, 2.8)] {
            lit.fill(Path(ellipseIn: CGRect(x: x - cr, y: y - cr, width: 2 * cr, height: 2 * cr)), with: .color(crater.opacity(0.45)))
        }
        for x in [18.5, 45.5] {
            lit.fill(Path(ellipseIn: CGRect(x: x - 3.2, y: 34.8, width: 6.4, height: 6.4)), with: .color(Color(hex: 0xFF9FB0).opacity(sleepy ? 0.25 : 0.6)))
        }
        lit.stroke(face, with: .color(Color(hex: 0x5B4630)), style: faceStyle)

        if sleepy {
            context.draw(Text("z").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0xC9CBE0)), at: CGPoint(x: 53, y: 10))
        } else if mood == .glowing {
            for (x, y, s) in [(55.0, 13.0, 5.0), (8.0, 50.0, 4.0)] {
                context.fill(sparkle(at: CGPoint(x: x, y: y), size: s), with: .color(Color(hex: 0xFFF3C4)))
            }
        }
    }

    private func facePath(sleepy: Bool) -> Path {
        var path = Path()
        for x in [20.0, 35.0] {
            path.move(to: CGPoint(x: x, y: sleepy ? 31 : 32))
            path.addQuadCurve(to: CGPoint(x: x + 9, y: sleepy ? 31 : 32), control: CGPoint(x: x + 4.5, y: sleepy ? 34.5 : 27))
        }
        if sleepy {
            path.move(to: CGPoint(x: 29.5, y: 41.5))
            path.addLine(to: CGPoint(x: 34.5, y: 41.5))
        } else {
            path.move(to: CGPoint(x: 27, y: 39.5))
            path.addQuadCurve(to: CGPoint(x: 37, y: 39.5), control: CGPoint(x: 32, y: 45))
        }
        return path
    }

    private func sparkle(at point: CGPoint, size s: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y - s))
        path.addQuadCurve(to: CGPoint(x: point.x + s, y: point.y), control: point)
        path.addQuadCurve(to: CGPoint(x: point.x, y: point.y + s), control: point)
        path.addQuadCurve(to: CGPoint(x: point.x - s, y: point.y), control: point)
        path.addQuadCurve(to: CGPoint(x: point.x, y: point.y - s), control: point)
        return path
    }
}

enum MoonPhase {
    static let synodicMonthDays = 29.530588853
    /// A known new moon: Jan 6 2000, 18:14 UTC.
    static let knownNewMoon = Date(timeIntervalSince1970: 947_182_440)

    /// Where the moon is in its cycle: 0 = new, 0.25 = first quarter, 0.5 = full.
    static func current(_ date: Date = .now) -> Double {
        let days = date.timeIntervalSince(knownNewMoon) / 86_400
        let cycles = days / synodicMonthDays
        return cycles - cycles.rounded(.down)
    }

    static func name(_ phase: Double) -> String {
        ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
         "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"][Int((phase * 8).rounded()) % 8]
    }

    /// The sunlit part of the disc: the limb on the lit side plus the terminator, a
    /// half-ellipse whose width follows the phase (thin crescent → half → nearly full).
    static func litPath(phase: Double, center: CGPoint, radius r: CGFloat) -> Path {
        let k = cos(2 * .pi * phase) // 1 at new moon, -1 at full
        let waxing = phase < 0.5 // waxing: lit on the right; waning: lit on the left
        let rx = max(abs(k) * r, 0.01)
        var path = Path()
        let steps = 48
        // Limb: a half circle on the lit side, top to bottom.
        for i in 0...steps {
            let angle = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            let x = center.x + (waxing ? 1 : -1) * r * cos(angle)
            let y = center.y + r * sin(angle)
            i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        // Terminator: bottom back to top, bulging toward the lit side for a crescent
        // (k > 0) and away from it for a gibbous moon (k < 0).
        let bulge: CGFloat = (k > 0) == waxing ? 1 : -1
        for i in 0...steps {
            let angle = Double.pi / 2 - Double.pi * Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: center.x + bulge * rx * cos(angle), y: center.y + r * sin(angle)))
        }
        path.closeSubpath()
        return path
    }
}

/// The logo: a crescent Luna and a lowercase rounded wordmark.
struct LogoView: View {
    var body: some View {
        HStack(spacing: 7) {
            LunaView(streak: 1, size: 24, phase: 0.82, animated: false)
                .shadow(color: .clear, radius: 0)
            Text("wakey \(Text("wakey").foregroundStyle(Color.wwAccent))")
                .foregroundStyle(Color.wwText)
                .font(.rounded(20))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wakey Wakey")
        .accessibilityAddTraits(.isHeader)
    }
}
