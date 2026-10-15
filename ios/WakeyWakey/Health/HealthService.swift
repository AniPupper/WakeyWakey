import Foundation
import HealthKit

/// One stretch of sleep read from Apple Health.
struct SleepSession: Equatable {
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A sleep stage as Health records it. Apple Watch writes REM/Core/Deep/Awake; iPhone and
/// other apps often only write "in bed" or plain "asleep".
enum SleepStage: Int, CaseIterable {
    case awake, rem, core, deep, asleep, inBed

    init?(healthValue: Int) {
        switch HKCategoryValueSleepAnalysis(rawValue: healthValue) {
        case .awake: self = .awake
        case .asleepREM: self = .rem
        case .asleepCore: self = .core
        case .asleepDeep: self = .deep
        case .asleepUnspecified: self = .asleep
        case .inBed: self = .inBed
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .asleep: "Asleep"
        case .inBed: "In bed"
        }
    }

    /// REM, Core or Deep: only recorded by Apple Watch.
    var isStage: Bool { self == .rem || self == .core || self == .deep }
    var isAsleep: Bool { isStage || self == .asleep }

    /// Which stage wins where samples overlap: Watch stages over awake over plain "asleep"
    /// over iPhone's "in bed".
    fileprivate var priority: Int {
        switch self {
        case .rem, .core, .deep: 3
        case .awake: 2
        case .asleep: 1
        case .inBed: 0
        }
    }
}

/// A stretch of one stage within a night.
struct SleepSegment: Equatable {
    var start: Date
    var end: Date
    var stage: SleepStage

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One night's sleep from Health, split into non-overlapping stage segments.
struct SleepNight: Identifiable, Equatable {
    /// Start of the day the night ended on.
    var morning: Date
    /// The session window, the same one an import uses.
    var start: Date
    var end: Date
    var segments: [SleepSegment]

    var id: Date { morning }
    /// False when Health only has "in bed" or plain "asleep" (no Apple Watch).
    var hasStages: Bool { segments.contains { $0.stage.isStage } }

    func minutes(_ stage: SleepStage) -> Int {
        Int((segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration } / 60).rounded())
    }

    /// Time asleep (all asleep stages), or time in bed when that's all there is.
    var asleepMinutes: Int {
        let asleep = segments.filter(\.stage.isAsleep).reduce(0) { $0 + $1.duration }
        let total = asleep > 0 ? asleep : segments.filter { $0.stage == .inBed }.reduce(0) { $0 + $1.duration }
        return Int((total / 60).rounded())
    }
}

/// Reads sleep from Apple Health so nights that weren't logged can be filled in.
/// Read-only: Wakey Wakey never writes to Health.
final class HealthService {
    static let shared = HealthService()

    /// How far back an import looks.
    static let lookbackDays = 30
    /// Samples this close together count as one session (e.g. a short wake in the night).
    static let maxGap: TimeInterval = 60 * 60
    /// Shorter sessions are naps, not nights.
    static let minSession: TimeInterval = 2 * 3600
    /// A night's session has to end before this hour (local time) to count for that morning.
    static let latestEndHour = 15

    private let store = HKHealthStore()
    private let sleep = HKCategoryType(.sleepAnalysis)

    /// False on devices without the Health app (e.g. some iPads).
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows Apple's Health permission sheet the first time; call this from a tap.
    /// HealthKit never says whether reading was allowed, so there's nothing to return.
    func requestAccess() async {
        guard Self.isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: [sleep])
    }

    /// The main sleep session for each morning in the last `lookbackDays`, at most one per
    /// morning: the longest session of at least `minSession` that ends before `latestEndHour`.
    /// Empty if there's no data or reading isn't allowed (HealthKit doesn't tell them apart).
    func sleepSessions(now: Date = .now, calendar: Calendar = .current) async -> [SleepSession] {
        guard Self.isAvailable,
              let from = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: calendar.startOfDay(for: now))
        else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleep, predicate: HKQuery.predicateForSamples(withStart: from, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)],
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let asleepOrInBed = samples.filter { $0.value != HKCategoryValueSleepAnalysis.awake.rawValue }
        return Self.mornings(Self.merge(asleepOrInBed.map { SleepSession(start: $0.startDate, end: $0.endDate) }), calendar: calendar)
    }

    /// The main night for each of the last `days` mornings (today included), oldest first,
    /// with its stages. Uses the same session rules as `sleepSessions`, so nights line up
    /// with what an import fills in. Empty if there's no data or reading isn't allowed.
    func sleepNights(days: Int = 7, now: Date = .now, calendar: Calendar = .current) async -> [SleepNight] {
        let today = calendar.startOfDay(for: now)
        guard let firstMorning = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let from = calendar.date(byAdding: .day, value: -1, to: firstMorning)
        else { return [] }
        #if DEBUG
        if let mock = Self.mockSegments(days: days, today: today, calendar: calendar) {
            return Self.nights(from: mock, firstMorning: firstMorning, calendar: calendar)
        }
        #endif
        guard Self.isAvailable else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleep, predicate: HKQuery.predicateForSamples(withStart: from, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)],
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let segments = samples.compactMap { sample in
            SleepStage(healthValue: sample.value).map { SleepSegment(start: sample.startDate, end: sample.endDate, stage: $0) }
        }
        return Self.nights(from: segments, firstMorning: firstMorning, calendar: calendar)
    }

    /// Picks each morning's session (as `sleepSessions` does, ignoring awake samples) and
    /// fills it with the stages inside its window.
    static func nights(from segments: [SleepSegment], firstMorning: Date, calendar: Calendar = .current) -> [SleepNight] {
        let sessions = mornings(merge(segments.filter { $0.stage != .awake }.map { SleepSession(start: $0.start, end: $0.end) }), calendar: calendar)
        return sessions
            .filter { calendar.startOfDay(for: $0.end) >= firstMorning }
            .map { session in
                SleepNight(
                    morning: calendar.startOfDay(for: session.end),
                    start: session.start,
                    end: session.end,
                    segments: flatten(segments, from: session.start, to: session.end),
                )
            }
    }

    /// Clips samples to the window and resolves overlaps, so every moment has at most one
    /// stage: the highest-priority sample covering it (e.g. Watch stages over iPhone's "in bed").
    static func flatten(_ samples: [SleepSegment], from start: Date, to end: Date) -> [SleepSegment] {
        let clipped = samples.compactMap { sample -> SleepSegment? in
            let a = max(sample.start, start), b = min(sample.end, end)
            return a < b ? SleepSegment(start: a, end: b, stage: sample.stage) : nil
        }
        let edges = Set(clipped.flatMap { [$0.start, $0.end] }).sorted()
        var result: [SleepSegment] = []
        for (a, b) in zip(edges, edges.dropFirst()) {
            let covering = clipped.filter { $0.start <= a && $0.end >= b }
            guard let top = covering.max(by: { ($0.stage.priority, $0.stage.rawValue) < ($1.stage.priority, $1.stage.rawValue) }) else { continue }
            if let last = result.last, last.stage == top.stage, last.end == a {
                result[result.count - 1].end = b
            } else {
                result.append(SleepSegment(start: a, end: b, stage: top.stage))
            }
        }
        return result
    }

    /// Joins overlapping or nearby samples into sessions.
    static func merge(_ samples: [SleepSession]) -> [SleepSession] {
        var sessions: [SleepSession] = []
        for sample in samples.sorted(by: { $0.start < $1.start }) where sample.end > sample.start {
            if let last = sessions.last, sample.start.timeIntervalSince(last.end) <= maxGap {
                sessions[sessions.count - 1].end = max(last.end, sample.end)
            } else {
                sessions.append(sample)
            }
        }
        return sessions
    }

    /// Keeps the longest qualifying session for each morning, oldest first.
    static func mornings(_ sessions: [SleepSession], calendar: Calendar = .current) -> [SleepSession] {
        var best: [Date: SleepSession] = [:]
        for session in sessions where session.duration >= minSession && calendar.component(.hour, from: session.end) < latestEndHour {
            let morning = calendar.startOfDay(for: session.end)
            if session.duration > best[morning]?.duration ?? 0 { best[morning] = session }
        }
        return best.values.sorted { $0.start < $1.start }
    }
}

#if DEBUG
/// Sample nights for the simulator, which has no Health sleep data. Only in debug builds,
/// and only when launched with `-mockSleep` (Watch stages), `-mockSleep noStages`
/// (iPhone "in bed" + plain "asleep"), `-mockSleep empty`, or `-mockSleep off` (card as if
/// Health import were off, without touching the saved setting).
extension HealthService {
    static var mockSleepMode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-mockSleep") else { return nil }
        let next = args.indices.contains(index + 1) ? args[index + 1] : ""
        return next.hasPrefix("-") || next.isEmpty ? "stages" : next
    }

    static func mockSegments(days: Int, today: Date, calendar: Calendar) -> [SleepSegment]? {
        guard let mode = mockSleepMode else { return nil }
        guard mode != "empty", mode != "off" else { return [] }
        var segments: [SleepSegment] = []
        for back in 0..<days where back != 4 { // one night without data
            let morning = calendar.date(byAdding: .day, value: -back, to: today)!
            var seed = UInt64(back + 7) &* 2_654_435_761
            func random() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 11) / Double(UInt64(1) << 53)
            }
            let start = morning.addingTimeInterval(-(50 + random() * 50) * 60)
            let end = morning.addingTimeInterval((6.6 + random() * 0.7) * 3600)
            // iPhone's "in bed", a bit wider than the Watch data.
            segments.append(SleepSegment(start: start.addingTimeInterval(-12 * 60), end: end.addingTimeInterval(6 * 60), stage: .inBed))
            guard mode != "noStages" else {
                segments.append(SleepSegment(start: start, end: end, stage: .asleep))
                continue
            }
            var t = start
            func add(_ stage: SleepStage, _ minutes: Double) {
                guard t < end, minutes > 0 else { return }
                let next = min(t.addingTimeInterval(minutes * 60), end)
                segments.append(SleepSegment(start: t, end: next, stage: stage))
                t = next
            }
            add(.core, 8 + random() * 10)
            var cycle = 0.0
            while t < end {
                add(.deep, max(0, 42 - cycle * 13 + random() * 10))
                add(.core, 22 + random() * 18)
                add(.rem, 9 + cycle * 7 + random() * 8)
                if random() < 0.55 { add(.awake, 1 + random() * 5) }
                add(.core, 8 + random() * 12)
                cycle += 1
            }
        }
        return segments
    }
}
#endif
