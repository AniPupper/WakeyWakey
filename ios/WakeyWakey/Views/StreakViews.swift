import SwiftUI

/// Luna and the streak number, handed to `content` to lay out. If the streak went up since
/// it was last shown, the number counts up with a pop, Luna hops, and sparkles burst out.
struct CelebratingStreak<Content: View>: View {
    var lunaSize: CGFloat
    @ViewBuilder var content: (_ luna: AnyView, _ number: AnyView) -> Content

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int?
    @State private var bump = false
    @State private var hop = false
    @State private var burst = 0

    var body: some View {
        let streak = store.streak
        let luna = LunaView(streak: streak, size: lunaSize)
            .rotationEffect(.degrees(hop ? -10 : 0))
            .offset(y: hop ? -12 : 0)
            .overlay { SparkleBurst(trigger: burst, radius: lunaSize * 0.75) }
        let number = Text("\(shown ?? streak)")
            .contentTransition(.numericText(value: Double(shown ?? streak)))
            .scaleEffect(bump ? 1.35 : 1)
        content(AnyView(luna), AnyView(number))
            .task(id: streak) { await celebrate(to: streak) }
    }

    private func celebrate(to streak: Int) async {
        let from = store.seenStreak
        store.seenStreak = streak
        guard streak > from, !reduceMotion else {
            shown = streak
            return
        }
        shown = from
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.spring(duration: 0.5, bounce: 0.5)) { hop = true }
        burst += 1
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(duration: 0.5, bounce: 0.4)) { hop = false }
        for value in (from + 1)...streak {
            withAnimation(.spring(duration: 0.25, bounce: 0.5)) {
                shown = value
                bump = true
            }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeOut(duration: 0.2)) { bump = false }
            try? await Task.sleep(for: .milliseconds(120))
        }
    }
}

/// Moon-gold sparkles flying outward each time `trigger` changes.
struct SparkleBurst: View {
    var trigger: Int
    var radius: CGFloat
    @State private var flying = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10 * 2 * .pi
                Circle()
                    .fill(Color.wwMoon)
                    .frame(width: 7, height: 7)
                    .shadow(color: .wwMoon, radius: 4)
                    .offset(x: flying ? cos(angle) * radius : 0, y: flying ? sin(angle) * radius : 0)
                    .scaleEffect(flying ? 0.3 : 1)
                    .opacity(flying ? 0 : (trigger == 0 ? 0 : 1))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            flying = false
            withAnimation(.easeOut(duration: 0.9)) { flying = true }
        }
    }
}

/// The last 7 wake-up days as small moons: kept, missed, still to come, or no alarm.
struct StreakPips: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let calendar = Calendar.current
        HStack {
            ForEach((0..<7).reversed(), id: \.self) { back in
                let date = calendar.date(byAdding: .day, value: -back, to: .now)!
                let entries = store.log.filter { calendar.isDate($0.alarmAt, inSameDayAs: date) }
                let status = status(back: back, date: date, entries: entries)
                VStack(spacing: 4) {
                    mark(status)
                    Text(SleepSchedule.dayLetters[SleepSchedule.dayIndex(of: date)])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(back == 0 ? Color.wwText : Color.wwMuted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(SleepSchedule.dayNames[SleepSchedule.dayIndex(of: date)]): \(status.rawValue)")
            }
        }
    }

    private enum Status: String { case kept, missed, notYet = "not yet", rest = "no alarm" }

    private func status(back: Int, date: Date, entries: [NightEntry]) -> Status {
        if entries.contains(where: \.wokeOnTime) { return .kept }
        if !store.schedule.plan(for: date).on { return .rest }
        if back == 0 && !entries.contains(where: { $0.stoppedAt != nil }) { return .notYet }
        return .missed
    }

    @ViewBuilder private func mark(_ status: Status) -> some View {
        switch status {
        case .kept:
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFF6D6), .wwMoon], center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 10))
                .frame(width: 18, height: 18)
                .shadow(color: .wwMoon.opacity(0.5), radius: 4)
        case .notYet:
            Circle().strokeBorder(Color.wwMoon, style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 18, height: 18)
        case .missed:
            Circle().strokeBorder(Color.wwSurface2, lineWidth: 2).frame(width: 18, height: 18)
        case .rest:
            Circle().fill(Color.wwSurface2).frame(width: 6, height: 6).frame(width: 18, height: 18)
        }
    }
}
