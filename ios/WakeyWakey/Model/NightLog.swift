import Foundation

/// One alarm's night and morning: when the phone went down, when she was up, and whether
/// she woke on her own (the PRD's success signal).
struct NightEntry: Codable, Hashable, Identifiable {
    var alarmAt: Date
    var bedtimeAt: Date?
    var phoneDownAt: Date?
    var stoppedAt: Date?
    var ownWake: Bool?
    /// Added by hand with "Log a night".
    var manual = false
    /// Recorded by the app, then changed by hand.
    var edited = false
    /// Filled in from Apple Health sleep data (and not changed by hand since).
    var imported = false

    var id: Date { alarmAt }

    init(alarmAt: Date) {
        self.alarmAt = alarmAt
    }

    /// Missing keys keep their defaults, so nights saved by an older version still load
    /// (otherwise one new field would make the whole log fail to decode).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alarmAt = try c.decode(Date.self, forKey: .alarmAt)
        bedtimeAt = try c.decodeIfPresent(Date.self, forKey: .bedtimeAt)
        phoneDownAt = try c.decodeIfPresent(Date.self, forKey: .phoneDownAt)
        stoppedAt = try c.decodeIfPresent(Date.self, forKey: .stoppedAt)
        ownWake = try c.decodeIfPresent(Bool.self, forKey: .ownWake)
        manual = try c.decodeIfPresent(Bool.self, forKey: .manual) ?? false
        edited = try c.decodeIfPresent(Bool.self, forKey: .edited) ?? false
        imported = try c.decodeIfPresent(Bool.self, forKey: .imported) ?? false
    }

    /// Minutes after the alarm she was up (0 if earlier).
    var minutesLate: Int {
        guard let stoppedAt else { return 0 }
        return max(0, Int((stoppedAt.timeIntervalSince(alarmAt) / 60).rounded()))
    }

    /// Minutes before the alarm she was up (0 if not early).
    var minutesEarly: Int {
        guard let stoppedAt else { return 0 }
        return max(0, Int((alarmAt.timeIntervalSince(stoppedAt) / 60).rounded()))
    }

    /// Minutes the phone went down before bedtime: positive = early, negative = late.
    var phoneDownMinutesEarly: Int? {
        guard let phoneDownAt, let bedtimeAt else { return nil }
        return Int((bedtimeAt.timeIntervalSince(phoneDownAt) / 60).rounded())
    }

    var phoneDownOnTime: Bool { (phoneDownMinutesEarly ?? -1) >= 0 }

    /// Up within a couple of minutes of the alarm (or before it), on her own.
    var wokeOnTime: Bool {
        stoppedAt != nil && minutesLate <= Streak.onTimeMinutes && ownWake != false
    }
}

enum Streak {
    /// Stopping the alarm within this many minutes counts as getting up right away.
    static let onTimeMinutes = 2

    /// Consecutive days, counting back from today, where she was up on her own right away.
    /// Nights logged by hand count the same. A day with no alarm doesn't break the streak,
    /// and adds to it if an on-time morning was logged anyway. (Uses today's schedule for
    /// past days, which is close enough for a streak.)
    static func current(log: [NightEntry], schedule: SleepSchedule, now: Date = .now, calendar: Calendar = .current) -> Int {
        var streak = 0
        for back in 0..<180 {
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { break }
            let entries = log.filter { $0.stoppedAt != nil && calendar.isDate($0.alarmAt, inSameDayAs: date) }
            if entries.contains(where: \.wokeOnTime) {
                streak += 1
                continue
            }
            let restDay = !schedule.plan(for: date).on
            let notYet = back == 0 && entries.isEmpty // today's alarm may not have rung yet
            if restDay || notYet { continue }
            break
        }
        return streak
    }
}
