import Foundation
import Observation

struct AppSettings: Codable, Hashable {
    /// A different chime each day (recommended), or always `toneName`.
    var rotateTones = true
    var toneName = Chimes.tones[0].name
    /// How loud the alarm gets, 0.1–1.
    var volume = 0.85
    /// Fill in nights that weren't logged from Apple Health sleep data.
    var importFromHealth = false

    init() {}

    /// Missing keys keep their defaults, so settings saved by an older version still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rotateTones = try c.decodeIfPresent(Bool.self, forKey: .rotateTones) ?? rotateTones
        toneName = try c.decodeIfPresent(String.self, forKey: .toneName) ?? toneName
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? volume
        importFromHealth = try c.decodeIfPresent(Bool.self, forKey: .importFromHealth) ?? importFromHealth
    }
}

/// The morning flow shown after an alarm is stopped: check-in, then the streak celebration.
struct MorningSession: Identifiable, Equatable {
    var alarmAt: Date
    var earlyWake = false
    var isTest = false
    var id: Date { alarmAt }
}

/// Everything the app remembers, saved to UserDefaults, plus keeping system alarms in sync.
@Observable
final class AppStore {
    static let shared = AppStore()

    /// Night mode started earlier than this before bedtime isn't logged as "phone down".
    static let phoneDownWindow: TimeInterval = 3 * 3600
    /// In the last stretch before the alarm, night mode offers "I'm already up".
    static let earlyWakeWindow: TimeInterval = 90 * 60

    var schedule: SleepSchedule { didSet { persist(schedule, Key.schedule); syncAlarms() } }
    var settings: AppSettings {
        didSet {
            persist(settings, Key.settings)
            if settings.rotateTones != oldValue.rotateTones || settings.toneName != oldValue.toneName || settings.volume != oldValue.volume {
                syncAlarms()
            }
        }
    }
    private(set) var log: [NightEntry] { didSet { persist(log, Key.log) } }
    /// The streak last shown, so the app can celebrate when it goes up.
    var seenStreak: Int { didSet { defaults.set(seenStreak, forKey: Key.seenStreak) } }
    /// Mornings whose alarm was skipped with "I'm already up".
    private var skippedAlarms: Set<Date> { didSet { persist(skippedAlarms, Key.skipped) } }
    /// Mornings (start of day) already handled by a Health import, so a night that was
    /// deleted or edited isn't filled in again (until the user taps "Refresh from Health").
    private var healthMornings: Set<Date> { didSet { persist(healthMornings, Key.healthMornings) } }

    var morning: MorningSession?
    var alarmPermission = AlarmService.shared.status
    /// The result of the last Health import, shown in Settings.
    var healthStatus: String?

    private let defaults = UserDefaults.standard
    private var syncTask: Task<Void, Never>?
    /// True while a Health import is running.
    private(set) var importing = false

    private enum Key {
        static let schedule = "schedule", settings = "settings", log = "nightLog"
        static let seenStreak = "seenStreak", skipped = "skippedAlarms", healthMornings = "healthImportedMornings"
    }

    private init() {
        schedule = Self.load(SleepSchedule.self, Key.schedule) ?? SleepSchedule()
        settings = Self.load(AppSettings.self, Key.settings) ?? AppSettings()
        log = Self.load([NightEntry].self, Key.log) ?? []
        seenStreak = UserDefaults.standard.integer(forKey: Key.seenStreak)
        skippedAlarms = Self.load(Set<Date>.self, Key.skipped) ?? []
        healthMornings = Self.load(Set<Date>.self, Key.healthMornings) ?? []
    }

    // MARK: Derived

    var sortedLog: [NightEntry] { log.sorted { $0.alarmAt < $1.alarmAt } }
    var nextAlarm: Date? { schedule.upcomingAlarms(days: 8).first { !skippedAlarms.contains($0) } }
    var streak: Int { Streak.current(log: log, schedule: schedule) }

    // MARK: Log

    func entry(for alarmAt: Date) -> NightEntry? { log.first { $0.alarmAt == alarmAt } }

    func updateEntry(_ alarmAt: Date, _ change: (inout NightEntry) -> Void) {
        if let index = log.firstIndex(where: { $0.alarmAt == alarmAt }) {
            change(&log[index])
        } else {
            var entry = NightEntry(alarmAt: alarmAt)
            change(&entry)
            log.append(entry)
        }
    }

    /// Saves a night entered or edited by hand, replacing the original (and anything else
    /// logged for that morning).
    func saveNight(_ entry: NightEntry, replacing original: NightEntry?) {
        let calendar = Calendar.current
        let replaced = log.filter { $0.alarmAt == original?.alarmAt || calendar.isDate($0.alarmAt, inSameDayAs: entry.alarmAt) }
        log.removeAll { replaced.contains($0) }
        log.append(entry)
    }

    func deleteNight(_ entry: NightEntry) {
        log.removeAll { $0.alarmAt == entry.alarmAt }
    }

    func clearHistory() {
        log = []
        seenStreak = 0
    }

    // MARK: Night and morning

    /// Starting night mode is the "phone down" moment, if it's close enough to bedtime.
    func startNight(now: Date = .now) {
        guard let alarm = nextAlarm else { return }
        let bedtime = schedule.bedtime(before: alarm)
        if bedtime.timeIntervalSince(now) <= Self.phoneDownWindow {
            updateEntry(alarm) {
                $0.phoneDownAt = now
                $0.bedtimeAt = bedtime
            }
        }
    }

    /// Called when "I'm up" is tapped on the system alarm (via `StopAlarmIntent`).
    func alarmStopped(alarmAt: Date, isTest: Bool, now: Date = .now) {
        if !isTest {
            updateEntry(alarmAt) {
                $0.stoppedAt = now
                if $0.bedtimeAt == nil { $0.bedtimeAt = schedule.bedtime(before: alarmAt) }
            }
        }
        morning = MorningSession(alarmAt: alarmAt, isTest: isTest)
    }

    /// Awake before the alarm: log it as up (which counts as on time) and skip the alarm.
    func wakeEarly(now: Date = .now) {
        guard let alarm = nextAlarm else { return }
        updateEntry(alarm) {
            $0.stoppedAt = now
            if $0.bedtimeAt == nil { $0.bedtimeAt = schedule.bedtime(before: alarm) }
        }
        skippedAlarms.insert(alarm)
        syncAlarms()
        morning = MorningSession(alarmAt: alarm, earlyWake: true)
    }

    func checkIn(ownWake: Bool) {
        guard let morning, !morning.isTest else { return }
        updateEntry(morning.alarmAt) { $0.ownWake = ownWake }
    }

    func canWakeEarly(now: Date = .now) -> Bool {
        guard let alarm = nextAlarm else { return false }
        return alarm.timeIntervalSince(now) <= Self.earlyWakeWindow
    }

    // MARK: Apple Health

    /// Turns importing from Apple Health on (showing Apple's permission sheet the first
    /// time, so call it from a tap) or off.
    func setImportFromHealth(_ on: Bool) async {
        guard on else {
            settings.importFromHealth = false
            healthStatus = nil
            return
        }
        await HealthService.shared.requestAccess()
        settings.importFromHealth = true
        await importFromHealth()
    }

    /// Fills in mornings from the last 30 days that have sleep in Health but nothing in the
    /// log. Existing nights are never changed, and each morning is only considered once.
    func importFromHealth(now: Date = .now) async {
        await runHealthImport(now: now, refresh: false)
    }

    /// Re-imports the last 30 days from Health, bringing back mornings that were handled
    /// before (including nights the user deleted). Nights already in the log are never changed.
    func refreshFromHealth(now: Date = .now) async {
        await runHealthImport(now: now, refresh: true)
    }

    private func runHealthImport(now: Date, refresh: Bool) async {
        guard settings.importFromHealth, HealthService.isAvailable, !importing else { return }
        importing = true
        defer { importing = false }
        if refresh {
            healthStatus = "Refreshing…"
        } else if healthStatus == nil {
            healthStatus = "Checking Health…"
        }

        let calendar = Calendar.current
        let sessions = await HealthService.shared.sleepSessions(now: now, calendar: calendar)
        guard settings.importFromHealth else { return }
        guard !sessions.isEmpty else {
            healthStatus = "No sleep data found in Health yet."
            return
        }
        // Forget which mornings were handled only once Health has answered, so a failed
        // or empty read doesn't let a later automatic import bring deleted nights back.
        if refresh { healthMornings.removeAll() }

        var added = 0
        for session in sessions {
            let morning = calendar.startOfDay(for: session.end)
            let alarmAt = schedule.plan(for: morning).wake.on(morning, calendar: calendar)
            // Today's alarm hasn't rung yet, so leave the morning to the alarm.
            guard alarmAt <= now, !healthMornings.contains(morning) else { continue }
            healthMornings.insert(morning)
            guard !log.contains(where: { calendar.isDate($0.alarmAt, inSameDayAs: morning) }) else { continue }
            var entry = NightEntry(alarmAt: alarmAt)
            entry.bedtimeAt = schedule.bedtime(before: alarmAt)
            entry.phoneDownAt = session.start
            entry.stoppedAt = session.end
            entry.imported = true
            log.append(entry)
            added += 1
        }
        healthStatus = added == 0 ? "Up to date" : "Imported \(added) night\(added == 1 ? "" : "s")"
    }

    // MARK: Alarms

    /// Re-schedules system alarms from the schedule and settings (debounced).
    func syncAlarms() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            skippedAlarms = skippedAlarms.filter { $0 > .now }
            alarmPermission = await AlarmService.shared.sync(schedule: schedule, settings: settings, skipping: skippedAlarms)
        }
    }

    /// Asks for permission to ring alarms (from a tap), then schedules them.
    func allowAlarms() async {
        _ = await AlarmService.shared.authorize()
        alarmPermission = AlarmService.shared.status
        syncAlarms()
    }

    func scheduleTestAlarm() async -> Bool {
        let scheduled = await AlarmService.shared.scheduleTest(settings: settings, in: 10)
        alarmPermission = AlarmService.shared.status
        if scheduled { syncAlarms() }
        return scheduled
    }

    // MARK: Persistence

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
