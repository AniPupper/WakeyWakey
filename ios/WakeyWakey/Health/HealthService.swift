import Foundation
import HealthKit

enum HealthPermission {
    /// This device has no Health app (e.g. some iPads).
    case unavailable
    case notAsked
    case allowed
    case denied
}

/// Saves each night's in-bed time (night mode → "I'm up") to Apple Health as Sleep data.
/// Write-only: Wakey Wakey never reads Health data (the PRD cuts sleep tracking).
final class HealthService {
    static let shared = HealthService()

    /// Nights longer than this are treated as mistakes and not saved (e.g. night mode left on).
    static let maxNight: TimeInterval = 16 * 3600
    /// Marks samples as Wakey Wakey's, keyed by the night's alarm time.
    static let alarmKey = "WakeyWakeyAlarm"

    private let store = HKHealthStore()
    private let sleep = HKCategoryType(.sleepAnalysis)

    var permission: HealthPermission {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch store.authorizationStatus(for: sleep) {
        case .sharingAuthorized: return .allowed
        case .sharingDenied: return .denied
        default: return .notAsked
        }
    }

    /// Shows Apple's Health permission sheet the first time; call this from a tap.
    func requestPermission() async -> HealthPermission {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        try? await store.requestAuthorization(toShare: [sleep], read: [])
        return permission
    }

    /// Whether a night has the times needed to save it.
    static func canSave(_ entry: NightEntry) -> Bool {
        guard let start = entry.phoneDownAt, let end = entry.stoppedAt else { return false }
        return end > start && end.timeIntervalSince(start) <= maxNight
    }

    /// Saves a night as "In Bed" time. Returns the new sample's ID, so it can be removed if
    /// the night is edited or deleted later.
    func save(_ entry: NightEntry) async -> UUID? {
        guard permission == .allowed, Self.canSave(entry), let start = entry.phoneDownAt, let end = entry.stoppedAt else {
            return nil
        }
        let sample = HKCategorySample(
            type: sleep,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
            start: start,
            end: end,
            metadata: [Self.alarmKey: entry.alarmAt.timeIntervalSince1970],
        )
        do {
            try await store.save(sample)
            return sample.uuid
        } catch {
            return nil
        }
    }

    /// Removes a sample Wakey Wakey saved earlier.
    func delete(sampleID: UUID) async {
        guard permission == .allowed else { return }
        _ = try? await store.deleteObjects(of: sleep, predicate: HKQuery.predicateForObject(with: sampleID))
    }
}
