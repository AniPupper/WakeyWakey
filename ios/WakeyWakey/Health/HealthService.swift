import Foundation
import HealthKit

/// One stretch of sleep read from Apple Health.
struct SleepSession: Equatable {
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
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
