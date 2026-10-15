import SwiftUI

struct HomeView: View {
    @Binding var tab: Tab
    @Binding var showNight: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                streakBox
                wakeCard.padding(.top, 12)
                bedButton.padding(.top, 20)
                if store.alarmPermission != .allowed { permissionCard.padding(.top, 12) }
                RhythmCard().padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Streak box

    private var streakBox: some View {
        Button { withAnimation { tab = .progress } } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    CelebratingStreak(lunaSize: 76) { luna, number in
                        luna
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                number
                                    .font(.rounded(44, .heavy))
                                    .foregroundStyle(store.streak == 0 ? Color.wwMuted : Color.wwMoon)
                                Text("night streak").font(.system(size: 19, weight: .bold))
                            }
                            Text(goalText)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.wwMuted)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Color.wwMuted)
                }
                Divider().overlay(Color.wwBorder).padding(.top, 12)
                StreakPips().padding(.top, 10)
            }
            .foregroundStyle(Color.wwText)
            .padding(EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 16))
            .card(glow: store.streak > 0 ? .wwMoon : nil)
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 16)
    }

    private var goalText: String {
        guard let next = store.nextAlarm else { return "Turn on an alarm to start a streak." }
        let upBy = next.addingTimeInterval(Double(Streak.onTimeMinutes) * 60)
        let when = "\(Format.time(upBy)) \(Format.relativeDay(next))"
        return store.streak > 0 ? "Up by \(when) to keep Luna glowing." : "Luna is asleep. Up by \(when) to start a streak."
    }

    // MARK: Wake-up card (the mockup)

    private var wakeCard: some View {
        Button { withAnimation { tab = .schedule } } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Wake Up set for")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.wwMuted)
                Text(store.nextAlarm.map { Format.time($0) } ?? "Off")
                    .font(.rounded(64))
                    .foregroundStyle(store.nextAlarm == nil ? Color.wwMuted : Color.wwText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Line()
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .frame(height: 2)
                    .padding(.vertical, 14)
                if let next = store.nextAlarm {
                    Text("\(Format.relativeDay(next).capitalized) · Bedtime \(Format.time(store.schedule.bedtime(before: next)))")
                        .font(.system(size: 17))
                    TimelineView(.everyMinute) { context in
                        Text("Rings in \(Format.duration(minutes: max(0, Int(next.timeIntervalSince(context.date) / 60))))")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.wwMuted)
                    }
                    .padding(.top, 4)
                } else {
                    Text("No alarms scheduled").font(.system(size: 17))
                }
                Label("Change times", systemImage: "alarm")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.wwAccent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Color.wwAccentSoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.wwAccent.opacity(0.5), lineWidth: 1.5))
                    .padding(.top, 18)
            }
            .foregroundStyle(Color.wwText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .card()
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Change alarm times")
    }

    // MARK: Bedtime

    private var bedButton: some View {
        TimelineView(.everyMinute) { context in
            Button(bedButtonTitle(now: context.date)) {
                store.startNight()
                showNight = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.nextAlarm == nil)
            .opacity(store.nextAlarm == nil ? 0.4 : 1)
        }
    }

    private func bedButtonTitle(now: Date) -> String {
        guard let next = store.nextAlarm else { return "Start night mode" }
        let bed = store.schedule.bedtime(before: next)
        if now >= bed { return "It's bedtime · Start night mode" }
        if bed.timeIntervalSince(now) <= 30 * 60 { return "Almost bedtime · Start night mode" }
        return "Start night mode"
    }

    /// Alarms need permission before they can ring. Asked from a tap, not at launch.
    private var permissionCard: some View {
        let denied = store.alarmPermission == .denied
        return VStack(alignment: .leading, spacing: 12) {
            Label(denied ? "Alarms are turned off" : "Turn on alarms", systemImage: denied ? "exclamationmark.triangle.fill" : "alarm.waves.left.and.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(denied ? Color.wwBad : Color.wwText)
            Text(denied
                 ? "Wakey Wakey can't ring until you allow alarms in the Settings app."
                 : "Wakey Wakey needs permission to ring your alarm, even when your phone is locked.")
                .font(.system(size: 14))
                .foregroundStyle(Color.wwMuted)
            Button(denied ? "Open Settings" : "Allow alarms") {
                if denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } else {
                    Task { await store.allowAlarms() }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .card()
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

/// "Your rhythm": one row per night on a shared 6 PM → noon axis: the planned window from
/// the schedule, and what happened (night mode to wake-up).
struct RhythmCard: View {
    @Environment(AppStore.self) private var store
    private static let spanHours = 18.0

    var body: some View {
        let calendar = Calendar.current
        let days = (0..<7).reversed().map { calendar.date(byAdding: .day, value: -$0, to: .now)! }
        VStack(alignment: .leading, spacing: 0) {
            Text("Your rhythm").font(.system(size: 20, weight: .bold))
            Text(summary(days: days))
                .font(.system(size: 14))
                .foregroundStyle(Color.wwMuted)
                .padding(.top, 3)
            VStack(spacing: 8) {
                ForEach(days, id: \.self) { day in row(day) }
            }
            .padding(.top, 14)
            GeometryReader { proxy in
                ForEach([(2.0, "8 PM"), (6.0, "12 AM"), (10.0, "4 AM"), (14.0, "8 AM")], id: \.1) { hours, label in
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.wwMuted)
                        .fixedSize()
                        .position(x: proxy.size.width * hours / Self.spanHours, y: 8)
                }
            }
            .frame(height: 16)
            .padding(.leading, 34)
            .padding(.top, 8)
            HStack(spacing: 16) {
                legend(Capsule().fill(Color.wwAccent), "Phone down to wake-up")
                legend(Capsule().strokeBorder(Color.wwAccent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])), "Your schedule")
            }
            .padding(.top, 12)
        }
        .foregroundStyle(Color.wwText)
        .padding(16)
        .card()
    }

    private func row(_ day: Date) -> some View {
        let calendar = Calendar.current
        let plan = store.schedule.plan(for: day)
        let entry = store.log.last { calendar.isDate($0.alarmAt, inSameDayAs: day) }
        return HStack(spacing: 0) {
            Text(SleepSchedule.shortDayNames[SleepSchedule.dayIndex(of: day)])
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(calendar.isDateInToday(day) ? Color.wwText : Color.wwMuted)
                .frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.03))
                    if plan.on && store.schedule.enabled {
                        let wake = plan.wake.on(day)
                        bar(from: store.schedule.bedtime(before: wake), to: wake, day: day, width: width)
                            .fill(Color.wwAccent.opacity(0.08))
                            .overlay(bar(from: store.schedule.bedtime(before: wake), to: wake, day: day, width: width)
                                .stroke(Color.wwAccent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                    if let entry, let down = entry.phoneDownAt {
                        bar(from: down, to: entry.stoppedAt ?? entry.alarmAt, day: day, width: width, inset: 3)
                            .fill(LinearGradient(colors: [Color(hex: 0x8B9CF7), .wwAccent], startPoint: .leading, endPoint: .trailing))
                            .opacity(entry.stoppedAt == nil ? 0.45 : 1)
                    } else if let entry, let up = entry.stoppedAt {
                        Capsule().fill(Color.wwAccent).frame(width: 8, height: 14).offset(x: x(up, day: day, width: width) - 4)
                    }
                }
            }
            .frame(height: 14)
        }
    }

    /// A rounded bar between two times, positioned on the night's axis.
    private func bar(from start: Date, to end: Date, day: Date, width: CGFloat, inset: CGFloat = 0) -> Path {
        let left = x(start, day: day, width: width)
        let right = max(x(end, day: day, width: width), left + 6)
        let rect = CGRect(x: left, y: inset, width: right - left, height: 14 - 2 * inset)
        return Path(roundedRect: rect, cornerRadius: rect.height / 2)
    }

    private func x(_ time: Date, day: Date, width: CGFloat) -> CGFloat {
        let start = Calendar.current.startOfDay(for: day).addingTimeInterval(-6 * 3600)
        let fraction = time.timeIntervalSince(start) / (Self.spanHours * 3600)
        return width * min(1, max(0, fraction))
    }

    private func summary(days: [Date]) -> String {
        let calendar = Calendar.current
        let entries = days.compactMap { day in store.log.last { calendar.isDate($0.alarmAt, inSameDayAs: day) }.map { (day, $0) } }
        func minutesIntoNight(_ time: Date, _ day: Date) -> Double {
            time.timeIntervalSince(calendar.startOfDay(for: day).addingTimeInterval(-6 * 3600)) / 60
        }
        let downs = entries.compactMap { day, e in e.phoneDownAt.map { minutesIntoNight($0, day) } }
        let ups = entries.compactMap { day, e in e.stoppedAt.map { minutesIntoNight($0, day) } }
        func spread(_ values: [Double]) -> Int? { values.count < 2 ? nil : Int(values.max()! - values.min()!) }
        let parts = [
            spread(downs).map { "Phone-down time varies by \(Format.duration(minutes: $0))" },
            spread(ups).map { "wake-up by \(Format.duration(minutes: $0))" },
        ].compactMap { $0 }
        return parts.isEmpty ? "Use night mode for a few nights to see how steady your routine is." : parts.joined(separator: " · ") + " this week."
    }

    private func legend(_ swatch: some View, _ text: String) -> some View {
        HStack(spacing: 6) {
            swatch.frame(width: 16, height: 8)
            Text(text).font(.system(size: 12)).foregroundStyle(Color.wwMuted)
        }
    }
}
