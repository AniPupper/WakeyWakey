import AVFoundation
import Foundation

// Gentle wake-up chimes. PRD: "Only a slight increase in volume; too gradual may result in
// lack of effectiveness. If we vary the ringtone then that might prevent her from getting
// used to and sleeping through the sound." So each chime starts clearly audible, rises a
// little, and a different melody plays each day.

struct Tone: Identifiable, Hashable {
    let name: String
    /// Frequencies in Hz; nil is a rest.
    let melody: [Double?]
    let noteSeconds: Double
    var id: String { name.lowercased() }
}

enum Chimes {
    private static let C5 = 523.25, D5 = 587.33, E5 = 659.25, G5 = 783.99, A5 = 880.0
    private static let C6 = 1046.5, D6 = 1174.66, E6 = 1318.51

    /// Pentatonic melodies, so every note combination sounds pleasant.
    static let tones: [Tone] = [
        Tone(name: "Sunrise", melody: [C5, E5, G5, C6, nil, G5, E5, nil], noteSeconds: 0.45),
        Tone(name: "Meadow", melody: [E5, G5, A5, G5, E5, nil, D5, nil], noteSeconds: 0.5),
        Tone(name: "Ripple", melody: [G5, A5, C6, D6, E6, nil, nil, nil], noteSeconds: 0.35),
        Tone(name: "Breeze", melody: [A5, G5, E5, D5, C5, nil, E5, nil], noteSeconds: 0.55),
        Tone(name: "Glow", melody: [C6, A5, G5, A5, C6, nil, E6, nil], noteSeconds: 0.4),
    ]

    /// The tone for an alarm: rotating by day by default, or the one chosen in Settings.
    static func tone(for date: Date, settings: AppSettings) -> Tone {
        guard settings.rotateTones else {
            return tones.first { $0.name == settings.toneName } ?? tones[0]
        }
        let dayNumber = Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
        return tones[((dayNumber % tones.count) + tones.count) % tones.count]
    }
}

/// Renders chimes to sound files in Library/Sounds, where system alarms can play them.
/// The volume is baked into the file, since an alarm's loudness can't be set any other way.
enum ChimeRenderer {
    static let sampleRate = 22_050.0
    /// Alarm sounds must be under 30 seconds; the system loops them while ringing.
    static let lengthSeconds = 28.0
    /// The file starts at this share of the volume and rises to full over `rampSeconds`.
    static let startRatio = 0.6
    static let rampSeconds = 16.0

    static func fileName(tone: Tone, volume: Double) -> String {
        "wakey-\(tone.id)-\(Int((volume * 100).rounded())).caf"
    }

    static var soundsDirectory: URL {
        URL.libraryDirectory.appending(path: "Sounds", directoryHint: .isDirectory)
    }

    /// The sound file for a tone at a volume, rendering it if it doesn't exist yet.
    @discardableResult
    static func ensureFile(tone: Tone, volume: Double) throws -> URL {
        let url = soundsDirectory.appending(path: fileName(tone: tone, volume: volume))
        if FileManager.default.fileExists(atPath: url.path()) { return url }
        try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        try write(render(tone: tone, volume: volume), to: url)
        return url
    }

    /// Deletes rendered files that aren't in `keep` (e.g. after the volume changes).
    static func removeFiles(except keep: Set<String>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: soundsDirectory.path())) ?? []
        for name in names where name.hasPrefix("wakey-") && !keep.contains(name) {
            try? FileManager.default.removeItem(at: soundsDirectory.appending(path: name))
        }
    }

    static func render(tone: Tone, volume: Double) -> [Float] {
        let total = Int(sampleRate * lengthSeconds)
        var samples = [Float](repeating: 0, count: total)
        let ring = Int(sampleRate * 1.6) // let each note ring past the next one
        let step = Int(sampleRate * tone.noteSeconds)
        var position = 0
        phrases: while position < total {
            for frequency in tone.melody {
                if let frequency {
                    for i in 0..<min(ring, total - position) {
                        samples[position + i] += Float(0.5 * bell(frequency, at: Double(i) / sampleRate))
                    }
                }
                position += step
                if position >= total { break phrases }
            }
            position += step * 2 // breathing room between phrases
        }
        let fade = Int(sampleRate * 0.4)
        for i in 0..<total {
            let rise = min(Double(i) / (sampleRate * rampSeconds), 1)
            var gain = volume * (startRatio + (1 - startRatio) * rise)
            if i > total - fade { gain *= Double(total - i) / Double(fade) }
            samples[i] = max(-1, min(1, samples[i] * Float(gain)))
        }
        return samples
    }

    /// A soft bell: a fundamental plus quiet overtones, quick attack, slow decay.
    private static func bell(_ frequency: Double, at t: Double) -> Double {
        let envelope = min(t / 0.01, 1) * exp(-3 * t)
        let wave = sin(2 * .pi * frequency * t)
            + 0.3 * sin(2 * .pi * frequency * 2 * t)
            + 0.1 * sin(2 * .pi * frequency * 3 * t)
        return envelope * wave / 1.4
    }

    private static func write(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buffer)
    }
}

/// Plays chimes in Settings: a tone preview, or a short burst after moving the volume slider.
@Observable
final class ChimePreview {
    private(set) var playingTone: String?
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ tone: Tone, volume: Double, seconds: Double) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: ChimeRenderer.ensureFile(tone: tone, volume: volume))
            player.play()
            self.player = player
            playingTone = tone.name
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { self?.stop() }
            }
        } catch {
            playingTone = nil
        }
    }

    func stop() {
        stopTask?.cancel()
        player?.stop()
        player = nil
        playingTone = nil
    }
}
