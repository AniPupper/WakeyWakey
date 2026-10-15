import SwiftUI

struct ProgressScreen: View {
    @Environment(AppStore.self) private var store
    /// The night being added (nil entry) or edited.
    @State private var editing: NightSheet?

    struct NightSheet: Identifiable {
        var entry: NightEntry?
        var id: Date { entry?.alarmAt ?? .distantPast }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PageTitle("Progress")
                    Spacer()
                    Button("+ Log a night") { editing = NightSheet(entry: nil) }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.wwAccent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Color.wwAccentSoft, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.wwAccent.opacity(0.5), lineWidth: 1.5))
                }
                streakCard
                PhoneDownCard(edit: { editing = NightSheet(entry: $0) })
                WakeUpsCard(edit: { editing = NightSheet(entry: $0) })
                howItWorks
            }
            .foregroundStyle(Color.wwText)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editing) { sheet in
            LogNightSheet(original: sheet.entry)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.wwSurface)
        }
    }

    private var streakCard: some View {
        VStack(spacing: 0) {
            CelebratingStreak(lunaSize: 96) { luna, number in
                VStack(spacing: 8) {
                    luna
                    number
                        .font(.rounded(64, .heavy))
                        .foregroundStyle(store.streak == 0 ? Color.wwMuted : Color.wwMoon)
                }
            }
            Text("night streak").font(.system(size: 17, weight: .bold)).padding(.top, 4)
            Text("Next goals")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.wwMuted)
                .padding(.top, 18)
                .padding(.bottom, 8)
            VStack(spacing: 6) {
                if let next = store.nextAlarm {
                    let upBy = next.addingTimeInterval(Double(Streak.onTimeMinutes) * 60)
                    goal("alarm", "Up by \(Format.time(upBy)) \(Format.relativeDay(next))")
                    goal("face.smiling", "On your own")
                } else {
                    goal("alarm", "Turn on an alarm to start a streak")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .card(glow: .wwMoon)
    }

    private func goal(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.wwMuted).frame(width: 22)
            Text(text).font(.system(size: 15))
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.wwSurface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How streaks work").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.wwText)
            Text("A morning adds to your streak when you hit both goals:")
            Text("**Up on time.** Tap \"I'm up\" within 2 minutes of the alarm. Awake before it? Tap \"I'm already up\" in night mode. That counts too.")
            Text("**On your own.** Answer \"Yes, on my own\" in the morning check-in.")
            Text("Phone-down time doesn't affect your streak. It's there to help you see your routine: green minutes mean your phone went down before bedtime, red minutes mean after.")
            Text("Days with no alarm don't break your streak. Forgot night mode? Use \"Log a night\" at the top to add it, and it still counts. Tap any night to edit or delete it.")
            Text("Luna changes with the real moon phase, and glows once your streak reaches a week.")
        }
        .font(.system(size: 15))
        .foregroundStyle(Color.wwMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }
}

/// Phone down, made easy to read: three headline numbers, then one line per night with the
/// time and how far it was from bedtime (green + early, red − late).
private struct PhoneDownCard: View {
    var edit: (NightEntry) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let nights = Array(store.sortedLog.filter { $0.phoneDownMinutesEarly != nil }.suffix(7))
        VStack(alignment: .leading, spacing: 0) {
            Text("Phone down").font(.system(size: 20, weight: .bold))
            if nights.isEmpty {
                Text("Start night mode tonight to begin tracking.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.wwMuted)
                    .padding(.vertical, 8)
            } else {
                let early = nights.compactMap(\.phoneDownMinutesEarly)
                let usualEarly = Int(median(early.map(Double.init)).rounded())
                HStack(spacing: 8) {
                    tile(Format.time(usualTime(nights)), "Usually down")
                    tile(Format.signed(minutes: usualEarly), "Vs. your goal", usualEarly >= 0 ? .wwGood : .wwBad)
                    tile("\(early.filter { $0 >= 0 }.count)/\(nights.count)", "Nights on time")
                }
                .padding(.top, 12)
                .padding(.bottom, 6)
                ForEach(nights.reversed()) { entry in
                    Divider().overlay(Color.wwBorder)
                    Button { edit(entry) } label: { row(entry) }
                        .buttonStyle(PressableStyle())
                }
                Text("Tap a night to edit or delete it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wwMuted)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private func row(_ entry: NightEntry) -> some View {
        let minutes = entry.phoneDownMinutesEarly ?? 0
        let color: Color = minutes >= 0 ? .wwGood : .wwBad
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(SleepSchedule.shortDayNames[SleepSchedule.dayIndex(of: entry.bedtimeAt ?? entry.alarmAt)])
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wwMuted)
                Text(Format.time(entry.phoneDownAt ?? entry.alarmAt)).font(.rounded(17))
            }
            .frame(width: 80, alignment: .leading)
            GeometryReader { proxy in
                let half = proxy.size.width / 2
                let length = half * min(Double(abs(minutes)), 60) / 60
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.04)).frame(height: 10)
                    Capsule().fill(color).frame(width: max(length, 4), height: 10)
                        .offset(x: minutes >= 0 ? half : half - max(length, 4))
                    Rectangle().fill(Color.wwMuted.opacity(0.5)).frame(width: 2, height: 16).offset(x: half - 1)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            Text(Format.signed(minutes: minutes))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 72, alignment: .trailing)
        }
        .foregroundStyle(Color.wwText)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.time(entry.phoneDownAt ?? entry.alarmAt)), \(minutes >= 0 ? "\(minutes) minutes early" : "\(-minutes) minutes late"). Edit")
    }

    private func tile(_ value: String, _ label: String, _ color: Color = .wwText) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.rounded(18)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 12)).foregroundStyle(Color.wwMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Color.wwSurface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The middle value, so one unusual night doesn't skew "usually".
    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// The median phone-down clock time, measured from 6 PM so nights crossing midnight compare.
    private func usualTime(_ nights: [NightEntry]) -> Date {
        let calendar = Calendar.current
        let minutes = nights.compactMap { entry -> Double? in
            guard let down = entry.phoneDownAt else { return nil }
            let start = calendar.startOfDay(for: entry.alarmAt).addingTimeInterval(-6 * 3600)
            return down.timeIntervalSince(start) / 60
        }
        let start = calendar.startOfDay(for: .now).addingTimeInterval(-6 * 3600)
        return start.addingTimeInterval(median(minutes) * 60)
    }
}

private struct WakeUpsCard: View {
    var edit: (NightEntry) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let wakeUps = Array(store.sortedLog.filter { $0.stoppedAt != nil }.suffix(7))
        VStack(alignment: .leading, spacing: 0) {
            Text("Wake-ups").font(.system(size: 20, weight: .bold))
            if wakeUps.isEmpty {
                Text("Your wake-ups show up here after the alarm rings.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.wwMuted)
                    .padding(.vertical, 8)
            } else {
                StreakPips().padding(.vertical, 12)
                ForEach(wakeUps.reversed()) { entry in
                    Divider().overlay(Color.wwBorder)
                    Button { edit(entry) } label: { row(entry) }
                        .buttonStyle(PressableStyle())
                }
                Text("Tap a night to edit or delete it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wwMuted)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private func row(_ entry: NightEntry) -> some View {
        let who = entry.ownWake == true ? " · On my own" : entry.ownWake == false ? " · Someone woke me" : ""
        let source = entry.manual ? " · Added by you" : entry.edited ? " · Edited" : entry.imported ? " · From Health" : ""
        let badge = entry.ownWake == false ? "Woken up"
            : entry.minutesEarly > 1 ? "\(entry.minutesEarly) min early"
            : entry.wokeOnTime ? "Right away" : "+\(entry.minutesLate) min"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.historyDate(entry.alarmAt)).font(.system(size: 17))
                Text("Alarm \(Format.time(entry.alarmAt)) · Up \(Format.time(entry.stoppedAt ?? entry.alarmAt))\(who)\(source)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wwMuted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Text(badge)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(entry.wokeOnTime ? Color.wwAccentText : Color.wwAccent)
                .background {
                    if entry.wokeOnTime { Capsule().fill(Color.wwAccent) } else { Capsule().strokeBorder(Color.wwAccent, lineWidth: 1.5) }
                }
        }
        .foregroundStyle(Color.wwText)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Add a missed night, or edit/delete one that's already logged.
struct LogNightSheet: View {
    var original: NightEntry?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var morning = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    @State private var alarm = ClockTime(hour: 7, minute: 0)
    @State private var phoneDown = ClockTime(hour: 22, minute: 0)
    @State private var woke = ClockTime(hour: 7, minute: 0)
    @State private var ownWake = true
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(original == nil ? "Log a missed night" : "Edit night").font(.system(size: 22, weight: .bold))
                    Text(original == nil
                         ? "Forgot night mode? Add what happened. This replaces anything already logged for that morning."
                         : "Change anything that's wrong, or delete this night.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.wwMuted)
                }
                HStack(alignment: .top, spacing: 10) {
                    labeled("Morning of") {
                        DatePicker("Morning of", selection: $morning, in: ...Date.now, displayedComponents: .date).labelsHidden()
                    }
                    labeled("Alarm was set for") { TimeField(label: "Alarm was set for", time: $alarm) }
                }
                HStack(alignment: .top, spacing: 10) {
                    labeled("Phone down") { TimeField(label: "Phone down", time: $phoneDown) }
                    labeled("Woke up") { TimeField(label: "Woke up", time: $woke) }
                }
                Toggle("Woke up on my own", isOn: $ownWake)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(14)
                    .background(Color.wwSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 10) {
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                    Button("Save", action: save).buttonStyle(PrimaryButtonStyle())
                }
                if original != nil {
                    Button("Delete this night", role: .destructive) { confirmDelete = true }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.wwBad)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .foregroundStyle(Color.wwText)
            .padding(.horizontal, 16)
            .padding(.top, 22)
        }
        .confirmationDialog("Delete this night?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let original { store.deleteNight(original) }
                dismiss()
            }
        }
        .onAppear(perform: fill)
        .onChange(of: morning) {
            // Picking another morning for a new night fills in that day's scheduled alarm.
            if original == nil { alarm = store.schedule.plan(for: morning).wake }
        }
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(Color.wwMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fill() {
        if let original {
            morning = original.alarmAt
            alarm = ClockTime(original.alarmAt)
            phoneDown = original.phoneDownAt.map { ClockTime($0) } ?? store.schedule.plan(for: original.alarmAt).bed
            woke = original.stoppedAt.map { ClockTime($0) } ?? alarm
            ownWake = original.ownWake != false
        } else {
            let plan = store.schedule.plan(for: morning)
            alarm = plan.wake
            phoneDown = plan.bed
            woke = plan.wake
        }
    }

    /// Saves as if night mode and the alarm had been used. A phone-down time in the
    /// afternoon or evening is taken as the night before.
    private func save() {
        let alarmAt = alarm.on(morning)
        var downAt = phoneDown.on(morning)
        if phoneDown.hour >= 12 { downAt = downAt.addingTimeInterval(-86_400) }
        let keepBedtime = original.flatMap { Calendar.current.isDate($0.alarmAt, inSameDayAs: morning) ? $0.bedtimeAt : nil }
        var entry = NightEntry(alarmAt: alarmAt)
        entry.bedtimeAt = keepBedtime ?? store.schedule.bedtime(before: alarmAt)
        entry.phoneDownAt = downAt
        entry.stoppedAt = woke.on(morning)
        entry.ownWake = ownWake
        if let original, !original.manual { entry.edited = true } else { entry.manual = true }
        store.saveNight(entry, replacing: original)
        dismiss()
    }
}
