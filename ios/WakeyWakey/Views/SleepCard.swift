import SwiftUI

extension SleepStage {
    /// Stage colors for the dark theme, from light (awake) to deep indigo (deep sleep).
    var color: Color {
        switch self {
        case .awake: Color(hex: 0xFF9580)
        case .rem: Color(hex: 0x67E8F9)
        case .core: .wwAccent
        case .deep: Color(hex: 0x6D6AF0)
        case .asleep: .wwAccent
        case .inBed: .wwSurface2
        }
    }

    /// The rows of the stages chart, top to bottom.
    static let chartRows: [SleepStage] = [.awake, .rem, .core, .deep]
}

/// Sleep from Apple Health: last night's total and stages, and the past week.
struct SleepCard: View {
    var openSettings: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sleep").font(.system(size: 20, weight: .bold))
            if !store.showsSleep {
                off
            } else if let nights = store.sleepNights {
                if let night = shownNight(nights) {
                    content(night, nights)
                } else {
                    message("No sleep data in Health yet.")
                }
            } else {
                ProgressView()
                    .tint(Color.wwMuted)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .accessibilityLabel("Loading sleep")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private var off: some View {
        VStack(alignment: .leading, spacing: 10) {
            message("Turn on \u{201C}Import from Apple Health\u{201D} in Settings to see your sleep and stages here.")
            Button(action: openSettings) {
                Text("Go to Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.wwAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Color.wwAccentSoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.wwAccent.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens Settings")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Color.wwMuted)
            .padding(.vertical, 8)
    }

    /// Today's night if there is one, otherwise the latest.
    private func shownNight(_ nights: [SleepNight]) -> SleepNight? {
        nights.first { Calendar.current.isDateInToday($0.morning) } ?? nights.last
    }

    @ViewBuilder
    private func content(_ night: SleepNight, _ nights: [SleepNight]) -> some View {
        let isToday = Calendar.current.isDateInToday(night.morning)
        VStack(alignment: .leading, spacing: 2) {
            Text(isToday ? "Last night" : Format.historyDate(night.morning))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.wwMuted)
            Text(Format.duration(minutes: night.asleepMinutes)).font(.rounded(30))
            Text("\(Format.time(night.start)) – \(Format.time(night.end))")
                .font(.system(size: 14))
                .foregroundStyle(Color.wwMuted)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isToday ? "Last night" : Format.historyDate(night.morning)): \(Format.duration(minutes: night.asleepMinutes)) asleep, \(Format.time(night.start)) to \(Format.time(night.end))")

        if night.hasStages {
            StagesChart(night: night)
                .padding(.top, 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep stages")
                .accessibilityValue(SleepStage.chartRows.map { "\($0.name) \(Format.duration(minutes: night.minutes($0)))" }.joined(separator: ", "))
            legend(night)
                .padding(.top, 12)
        } else {
            Label("Sleep stages need an Apple Watch.", systemImage: "applewatch")
                .font(.system(size: 13))
                .foregroundStyle(Color.wwMuted)
                .padding(.top, 10)
        }

        Divider().overlay(Color.wwBorder).padding(.vertical, 14)
        WeekSleepChart(nights: nights, highlighted: night.morning)

        Text("From Apple Health.")
            .font(.system(size: 12))
            .foregroundStyle(Color.wwMuted)
            .padding(.top, 12)
    }

    private func legend(_ night: SleepNight) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(SleepStage.chartRows, id: \.self) { stage in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(stage.color).frame(width: 10, height: 10)
                    Text(stage.name).font(.system(size: 14, weight: .semibold))
                    Text(Format.duration(minutes: night.minutes(stage)))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.wwMuted)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Last night's stages over time, one row per stage, like the Health app's chart.
private struct StagesChart: View {
    var night: SleepNight

    private static let rowHeight: CGFloat = 28
    private static let labelWidth: CGFloat = 56

    var body: some View {
        let rows = SleepStage.chartRows
        let span = max(night.end.timeIntervalSince(night.start), 1)
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.self) { stage in
                        Text(stage.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(stage.color)
                            .frame(height: Self.rowHeight)
                    }
                }
                .frame(width: Self.labelWidth, alignment: .leading)
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .topLeading) {
                        ForEach(hours, id: \.self) { hour in
                            Rectangle()
                                .fill(Color.wwBorder)
                                .frame(width: 1, height: proxy.size.height)
                                .offset(x: width * hour.timeIntervalSince(night.start) / span)
                        }
                        ForEach(rows.indices, id: \.self) { index in
                            Rectangle()
                                .fill(Color.wwBorder)
                                .frame(height: 1)
                                .offset(y: Self.rowHeight * CGFloat(index + 1) - 0.5)
                        }
                        ForEach(night.segments.filter { rows.contains($0.stage) }, id: \.start) { segment in
                            let row = rows.firstIndex(of: segment.stage) ?? 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(segment.stage.color)
                                .frame(width: max(2, width * segment.duration / span), height: Self.rowHeight - 10)
                                .offset(x: width * segment.start.timeIntervalSince(night.start) / span,
                                        y: Self.rowHeight * CGFloat(row) + 5)
                        }
                    }
                }
                .frame(height: Self.rowHeight * CGFloat(rows.count))
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.labelWidth, height: 1)
                GeometryReader { proxy in
                    ForEach(hours, id: \.self) { hour in
                        Text(hour.formatted(.dateTime.hour()))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.wwMuted)
                            .fixedSize()
                            .frame(width: 44)
                            .position(x: min(max(22, proxy.size.width * hour.timeIntervalSince(night.start) / span), proxy.size.width - 22),
                                      y: 7)
                    }
                }
                .frame(height: 14)
            }
        }
    }

    /// Every other whole hour inside the night, for the time axis.
    private var hours: [Date] {
        let calendar = Calendar.current
        guard var hour = calendar.nextDate(after: night.start, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
        else { return [] }
        if calendar.component(.hour, from: hour) % 2 == 1 { hour = hour.addingTimeInterval(3600) }
        var result: [Date] = []
        while hour < night.end {
            result.append(hour)
            hour = hour.addingTimeInterval(2 * 3600)
        }
        return result
    }
}

/// Time asleep for each of the last 7 mornings, today on the right.
private struct WeekSleepChart: View {
    var nights: [SleepNight]
    var highlighted: Date

    private static let barHeight: CGFloat = 64

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = (0..<7).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
        let minutes = days.map { day in nights.first { calendar.isDate($0.morning, inSameDayAs: day) }?.asleepMinutes }
        let known = minutes.compactMap { $0 }
        let average = known.isEmpty ? 0 : known.reduce(0, +) / known.count
        let scale = Double(max(known.max() ?? 0, 9 * 60))

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Averaging \(Format.duration(minutes: average))")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wwMuted)
            }
            HStack(alignment: .bottom) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let value = minutes[index]
                    let isHighlighted = calendar.isDate(day, inSameDayAs: highlighted)
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            Color.clear
                            if let value {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.wwAccent.opacity(isHighlighted ? 1 : 0.45))
                                    .frame(width: 18, height: max(4, Self.barHeight * Double(value) / scale))
                            } else {
                                Circle().fill(Color.wwSurface2).frame(width: 6, height: 6)
                            }
                        }
                        .frame(height: Self.barHeight)
                        Text(SleepSchedule.dayLetters[SleepSchedule.dayIndex(of: day)])
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(index == 6 ? Color.wwText : Color.wwMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: averaging \(Format.duration(minutes: average)) asleep")
        .accessibilityValue(days.indices.map { index in
            "\(SleepSchedule.dayNames[SleepSchedule.dayIndex(of: days[index])]) \(minutes[index].map { Format.duration(minutes: $0) } ?? "no data")"
        }.joined(separator: ", "))
    }
}
