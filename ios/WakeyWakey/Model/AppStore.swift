import Foundation
import Observation

struct AppSettings: Codable, Hashable {
    /// A different chime each day (recommended), or always `toneName`.
    var rotateTones = true
    var toneName = Chimes.tones[0].name
    /// How loud the alarm gets, 0.1–1.
    var volume = 0.85
    /// Save each night's in-bed time to Apple Health.
    var saveToHealth = false

    init() {}

    /// Missing keys keep their defaults, so settings saved by an older version still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rotateTones = try c.decodeIfPresent(Bool.self, forKey: .rotateTones) ?? rotateTones
        toneName = try c.decodeIfPresent(String.self, forKey: .toneName) ?? toneName
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? volume
        saveToHealth = try c.decodeIfPresent(Bool.self, forKey: .saveToHealth) ?? saveToHealth
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
    private(set) var log: [NightEntry] {
        didSet {
            persist(log, Key.log)
            if !recordingHealthIDs { syncHealth() }
        }
    }
    /// The streak last shown, so the app can celebrate when it goes up.
    var seenStreak: Int { didSet { defaults.set(seenStreak, forKey: Key.seenStreak) } }
    /// Mornings whose alarm was skipped with "I'm already up".
    private var skippedAlarms: Set<Date> { didSet { persist(skippedAlarms, Key.skipped) } }

    var morning: MorningSession?
    var alarmPermission = AlarmService.shared.status
    var healthPermission = HealthService.shared.permission

    private let defaults = UserDefaults.standard
    private var syncTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    /// Set while saving Health sample IDs, so that bookkeeping doesn't start another sync.
    private var recordingHealthIDs = false

    private enum Key {
        static let schedule = "schedule", settings = "settings", log = "nightLog"
        static let seenStreak = "seenStreak", skipped = "skippedAlarms"
    }

    private init() {
        schedule = Self.load(SleepSchedule.self, Key.schedule) ?? SleepSchedule()
        settings = Self.load(AppSettings.self, Key.settings) ?? AppSettings()
        log = Self.load([NightEntry].self, Key.log) ?? []
        seenStreak = UserDefaults.standard.integer(forKey: Key.seenStreak)
        skippedAlarms = Self.load(Set<Date>.self, Key.skipped) ?? []
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
        removeFromHealth(replaced)
        log.removeAll { replaced.contains($0) }
        log.append(entry)
    }

    func deleteNight(_ entry: NightEntry) {
        removeFromHealth(log.filter { $0.alarmAt == entry.alarmAt })
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

    /// Turns saving to Apple Health on (asking for permission the first time) or off.
    func setSaveToHealth(_ on: Bool) async {
        guard on else {
            settings.saveToHealth = false
            return
        }
        healthPermission = await HealthService.shared.requestPermission()
        settings.saveToHealth = healthPermission == .allowed
        syncHealth()
    }

    /// Saves any finished nights that aren't in Health yet (debounced).
    func syncHealth() {
        guard settings.saveToHealth else { return }
        healthTask?.cancel()
        healthTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            healthPermission = HealthService.shared.permission
            for entry in log where entry.healthSampleID == nil && HealthService.canSave(entry) {
                guard let id = await HealthService.shared.save(entry) else { continue }
                recordingHealthIDs = true
                if let index = log.firstIndex(where: { $0.alarmAt == entry.alarmAt }) { log[index].healthSampleID = id }
                recordingHealthIDs = false
            }
        }
    }

    private func removeFromHealth(_ entries: [NightEntry]) {
        let ids = entries.compactMap(\.healthSampleID)
        guard !ids.isEmpty else { return }
        Task { for id in ids { await HealthService.shared.delete(sampleID: id) } }
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
