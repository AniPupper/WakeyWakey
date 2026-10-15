import Foundation

/// A time of day, like 7:30.
struct ClockTime: Codable, Hashable {
    var hour: Int
    var minute: Int

    /// This time on the same calendar day as `date`.
    func on(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    /// For binding to a `DatePicker`, which edits a full `Date`.
    var asDate: Date { on(.now) }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? 0
        minute = parts.minute ?? 0
    }
}

/// One day of the schedule: whether the alarm rings, the wake-up time, and the bedtime
/// the night before.
struct DayPlan: Codable, Hashable {
    var on: Bool
    var bed: ClockTime
    var wake: ClockTime

    /// Minutes between bedtime and the wake-up time.
    var sleepMinutes: Int {
        let reference = Date(timeIntervalSinceReferenceDate: 86_400 * 2)
        let wakeAt = wake.on(reference)
        var bedAt = bed.on(reference)
        if bedAt >= wakeAt { bedAt = bedAt.addingTimeInterval(-86_400) }
        return Int(wakeAt.timeIntervalSince(bedAt) / 60)
    }
}

/// How the schedule is edited: one set of times, weekdays and weekend together, or each
/// day on its own.
enum ScheduleMode: String, Codable, CaseIterable, Identifiable {
    case everyday, weekdays, custom
    var id: Self { self }

    var title: String {
        switch self {
        case .everyday: "Every day"
        case .weekdays: "Weekdays"
        case .custom: "Custom"
        }
    }
}

/// Day indexes follow the calendar: 0 = Sunday … 6 = Saturday.
struct SleepSchedule: Codable, Hashable {
    static let weekdays = [1, 2, 3, 4, 5]
    static let weekend = [6, 0]
    /// The school week first.
    static let allDays = [1, 2, 3, 4, 5, 6, 0]
    static let dayNames = Calendar.current.weekdaySymbols
    static let shortDayNames = Calendar.current.shortWeekdaySymbols
    static let dayLetters = Calendar.current.veryShortWeekdaySymbols

    var enabled = true
    var mode: ScheduleMode = .weekdays
    /// School days on, weekends off.
    var days: [DayPlan] = (0..<7).map { day in
        DayPlan(on: (1...5).contains(day), bed: ClockTime(hour: 22, minute: 0), wake: ClockTime(hour: 6, minute: 30))
    }

    static func dayIndex(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    func plan(for date: Date) -> DayPlan {
        days[Self.dayIndex(of: date)]
    }

    /// The next time the alarm should ring after `now`, if any.
    func nextAlarm(after now: Date = .now, calendar: Calendar = .current) -> Date? {
        upcomingAlarms(from: now, days: 8, calendar: calendar).first
    }

    /// Every alarm from `now` through the next `days` days.
    func upcomingAlarms(from now: Date = .now, days count: Int, calendar: Calendar = .current) -> [Date] {
        guard enabled else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let plan = plan(for: date)
            let alarm = plan.wake.on(date, calendar: calendar)
            return plan.on && alarm > now ? alarm : nil
        }
    }

    /// The bedtime leading up to an alarm: the latest moment at that day's bedtime before it.
    func bedtime(before alarm: Date) -> Date {
        let bed = plan(for: alarm).bed.on(alarm)
        return bed >= alarm ? bed.addingTimeInterval(-86_400) : bed
    }

    /// Sets the same values on every day in a group, e.g. all weekdays at once.
    mutating func update(_ indexes: [Int], _ change: (inout DayPlan) -> Void) {
        for index in indexes { change(&days[index]) }
    }

    /// Switches editing mode, making the days consistent with it. Times carry over from
    /// the first weekday with an alarm, so switching never throws away what was set.
    mutating func switchMode(to newMode: ScheduleMode) {
        let template = Self.weekdays.map { days[$0] }.first(where: \.on) ?? days.first(where: \.on) ?? days[1]
        switch newMode {
        case .everyday:
            update(Self.allDays) { $0 = DayPlan(on: true, bed: template.bed, wake: template.wake) }
        case .weekdays:
            update(Self.weekdays) { $0 = DayPlan(on: true, bed: template.bed, wake: template.wake) }
            let saturday = days[6]
            update(Self.weekend) { $0 = saturday }
        case .custom:
            break
        }
        mode = newMode
    }
}
