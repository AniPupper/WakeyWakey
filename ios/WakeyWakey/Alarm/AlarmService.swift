import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI

enum AlarmPermission {
    case allowed, notAsked, denied
}

nonisolated struct WakeMetadata: AlarmMetadata {
    var isTest = false
}

/// Schedules real system alarms with AlarmKit, so they ring even when the phone is locked
/// and the app is closed. Each morning is its own alarm, so each can have that day's chime.
final class AlarmService {
    static let shared = AlarmService()

    /// How far ahead alarms are scheduled; opening the app tops this up.
    static let daysAhead = 14

    private let manager = AlarmManager.shared

    var status: AlarmPermission {
        switch manager.authorizationState {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    /// Shows Apple's permission prompt the first time; call this from a tap.
    func authorize() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        default:
            return false
        }
    }

    /// Replaces all scheduled wake-up alarms with the ones the schedule calls for. Does
    /// nothing until alarms are allowed.
    func sync(schedule: SleepSchedule, settings: AppSettings, skipping skipped: Set<Date>) async -> AlarmPermission {
        guard status == .allowed else { return status }
        for alarm in (try? manager.alarms) ?? [] where alarm.state != .alerting {
            _ = try? manager.cancel(id: alarm.id)
        }
        var soundFiles = Set<String>()
        for date in schedule.upcomingAlarms(days: Self.daysAhead) where !skipped.contains(date) {
            let tone = Chimes.tone(for: date, settings: settings)
            guard let file = try? ChimeRenderer.ensureFile(tone: tone, volume: settings.volume) else { continue }
            soundFiles.insert(file.lastPathComponent)
            _ = try? await manager.schedule(id: UUID(), configuration: configuration(at: date, sound: file.lastPathComponent, isTest: false))
        }
        ChimeRenderer.removeFiles(except: soundFiles)
        return .allowed
    }

    /// A one-off alarm a few seconds from now, to try the whole morning without logging.
    func scheduleTest(settings: AppSettings, in seconds: TimeInterval) async -> Bool {
        guard await authorize() else { return false }
        let date = Date.now.addingTimeInterval(seconds)
        let tone = Chimes.tone(for: .now, settings: settings)
        guard let file = try? ChimeRenderer.ensureFile(tone: tone, volume: settings.volume) else { return false }
        do {
            _ = try await manager.schedule(id: UUID(), configuration: configuration(at: date, sound: file.lastPathComponent, isTest: true))
            return true
        } catch {
            return false
        }
    }

    private func configuration(at date: Date, sound: String, isTest: Bool) -> AlarmManager.AlarmConfiguration<WakeMetadata> {
        let stop = AlarmButton(text: "I'm up", textColor: Color.wwAccentText, systemImageName: "sun.max.fill")
        let alert = AlarmPresentation.Alert(title: isTest ? "Test alarm" : "Wakey wakey", stopButton: stop)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeMetadata(isTest: isTest),
            tintColor: Color.wwAccent,
        )
        return AlarmManager.AlarmConfiguration(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmAt: date.timeIntervalSince1970, isTest: isTest),
            sound: .named(sound),
        )
    }
}

/// Runs when "I'm up" is tapped on the alarm: logs the wake-up and opens the app to the
/// morning check-in.
struct StopAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I'm up"
    static let openAppWhenRun = true

    @Parameter(title: "Alarm time")
    var alarmAt: Double

    @Parameter(title: "Test alarm")
    var isTest: Bool

    init() {
        alarmAt = 0
        isTest = false
    }

    init(alarmAt: Double, isTest: Bool) {
        self.alarmAt = alarmAt
        self.isTest = isTest
    }

    func perform() async throws -> some IntentResult {
        await AppStore.shared.alarmStopped(alarmAt: Date(timeIntervalSince1970: alarmAt), isTest: isTest)
        return .result()
    }
}
