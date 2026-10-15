import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var preview = ChimePreview()
    @State private var volume = 85.0
    @State private var testStatus: String?
    @State private var confirmClear = false
    @State private var cleared = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("Wake-up sound")
                volumeCard
                Toggle(isOn: $store.settings.rotateTones) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Different chime each day").font(.system(size: 17, weight: .semibold))
                        Text("Changing the sound keeps you from getting used to it and sleeping through.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.wwMuted)
                    }
                }
                .padding(16)
                .card()
                .padding(.top, 12)

                section(store.settings.rotateTones ? "Chimes in rotation" : "Your chime")
                toneList
                footnote("Every chime starts a little softer and builds to your alarm volume. While you're testing Wakey Wakey, keep a backup alarm set in the Clock app.")

                if store.healthPermission != .unavailable {
                    section("Apple Health")
                    healthCard
                    footnote(healthFootnote)
                }

                section("Testing")
                Button(action: runTest) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Test the alarm").font(.system(size: 17, weight: .semibold))
                            Text(testStatus ?? "Rings in 10 seconds with your chime and volume.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.wwMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.wwMuted)
                    }
                    .foregroundStyle(Color.wwText)
                    .padding(16)
                    .card()
                }
                .buttonStyle(PressableStyle())
                footnote("A real system alarm rings, even if you lock the phone. Tap \"I'm up\" to see the check-in and celebration. Nothing is logged and your streak doesn't change.")

                section("Data")
                Button(cleared ? "History cleared" : "Clear history") { confirmClear = true }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.wwBad)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 16)
                    .card()
                footnote("Removes your wake-ups, phone-down times and streak, for example after testing. Your schedule and settings stay.")
            }
            .foregroundStyle(Color.wwText)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { volume = (store.settings.volume * 100).rounded() }
        .onDisappear { preview.stop() }
        .confirmationDialog("Clear all wake-ups, phone-down times and your streak?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) {
                store.clearHistory()
                cleared = true
            }
        } message: {
            Text("Your schedule and settings stay.")
        }
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Alarm volume").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(Int(volume))%").font(.rounded(17)).foregroundStyle(Color.wwAccent)
            }
            Slider(value: $volume, in: 10...100, step: 5) {
                Text("Alarm volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill").foregroundStyle(Color.wwMuted)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(Color.wwMuted)
            } onEditingChanged: { editing in
                guard !editing else { return }
                // Let go of the slider to hear it.
                store.settings.volume = volume / 100
                preview.play(Chimes.tone(for: .now, settings: store.settings), volume: store.settings.volume, seconds: 2.5)
            }
            Text("How loud the alarm gets. Let go of the slider to hear it. This works on top of your phone's own volume, so keep that turned up.")
                .font(.system(size: 14))
                .foregroundStyle(Color.wwMuted)
        }
        .padding(16)
        .card()
    }

    private var healthCard: some View {
        Toggle(isOn: Binding(
            get: { store.settings.saveToHealth },
            set: { on in Task { await store.setSaveToHealth(on) } },
        )) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color(hex: 0xFF3B5C), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Save to Apple Health").font(.system(size: 17, weight: .semibold))
                    Text("Adds your in-bed time each night, from night mode to \"I'm up\".")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.wwMuted)
                }
            }
        }
        .padding(16)
        .card()
    }

    private var healthFootnote: String {
        if store.healthPermission == .denied {
            return "Health access is turned off. To turn it on, open the Health app, tap your profile, then Apps → Wakey Wakey."
        }
        return "Shows up in the Health app under Sleep. Wakey Wakey only adds data and never reads your health information. Editing or deleting a night here updates Health too."
    }

    private var toneList: some View {
        let today = Chimes.tone(for: .now, settings: AppSettings())
        return VStack(spacing: 0) {
            ForEach(Array(Chimes.tones.enumerated()), id: \.element.id) { index, tone in
                if index > 0 { Divider().overlay(Color.wwBorder) }
                HStack(spacing: 12) {
                    Button {
                        store.settings.toneName = tone.name
                    } label: {
                        HStack {
                            Text(tone.name).font(.system(size: 17))
                            if store.settings.rotateTones && tone == today {
                                Text("· Today").foregroundStyle(Color.wwMuted)
                            }
                            Spacer()
                            if !store.settings.rotateTones && store.settings.toneName == tone.name {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.wwAccent)
                            }
                        }
                        .foregroundStyle(Color.wwText)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .disabled(store.settings.rotateTones)
                    .accessibilityAddTraits(!store.settings.rotateTones && store.settings.toneName == tone.name ? .isSelected : [])

                    let playing = preview.playingTone == tone.name
                    Button {
                        playing ? preview.stop() : preview.play(tone, volume: store.settings.volume, seconds: 8)
                    } label: {
                        Image(systemName: playing ? "stop.fill" : "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.wwAccent)
                            .frame(width: 36, height: 36)
                            .background(Color.wwAccentSoft, in: Circle())
                    }
                    .accessibilityLabel("\(playing ? "Stop" : "Play") \(tone.name)")
                }
            }
        }
        .padding(.horizontal, 16)
        .card()
    }

    private func runTest() {
        preview.stop()
        testStatus = "Scheduling…"
        Task {
            let scheduled = await store.scheduleTestAlarm()
            testStatus = scheduled
                ? "Test alarm set for \(Format.time(.now.addingTimeInterval(10))). Lock the phone if you like."
                : "Alarms aren't allowed. Turn them on for Wakey Wakey in the Settings app."
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Color.wwMuted)
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 8)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.wwMuted)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }
}
