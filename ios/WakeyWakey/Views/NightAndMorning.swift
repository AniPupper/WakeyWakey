import SwiftUI

/// Night mode: a near-black clock. The alarm rings through the system either way, so the
/// phone can be locked; opening this logs "phone down".
struct NightView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 8) {
                Spacer()
                Text(Format.time(context.date))
                    .font(.rounded(88, .light))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(store.nextAlarm.map { "Alarm \(Format.time($0))" } ?? "No alarm set")
                    .font(.system(size: 17))
                Text("You can lock your phone. The alarm still rings.")
                    .font(.system(size: 14))
                    .padding(.top, 4)
                if store.canWakeEarly(now: context.date) {
                    Button("I'm already up") {
                        dismiss()
                        // Let night mode finish closing before the check-in opens.
                        Task {
                            try? await Task.sleep(for: .milliseconds(600))
                            store.wakeEarly()
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x8D90AD))
                    .padding(.horizontal, 24)
                    .frame(minHeight: 48)
                    .overlay(Capsule().strokeBorder(Color(hex: 0x3A3C52), lineWidth: 1.5))
                    .padding(.top, 36)
                }
                Spacer()
                Button("Exit night mode") { dismiss() }
                    .font(.system(size: 15))
                    .padding(.bottom, 20)
            }
            .foregroundStyle(Color.wwNightText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .background(Color.black.ignoresSafeArea())
        }
        .statusBarHidden()
    }
}

/// After "I'm up": a one-tap check-in (the PRD's success signal: she woke on her own),
/// then the streak celebration.
struct MorningView: View {
    var session: MorningSession
    @Environment(AppStore.self) private var store
    @State private var answered = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            if !answered {
                checkIn.transition(.opacity.combined(with: .offset(y: 12)))
            } else {
                celebration.transition(.opacity.combined(with: .offset(y: 12)))
            }
            Spacer()
        }
        .foregroundStyle(Color.wwText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
    }

    private var checkIn: some View {
        VStack(spacing: 0) {
            Text(session.earlyWake ? "Up before your alarm!" : "Nice, you're up!").font(.system(size: 24, weight: .semibold))
            Text("Did you wake up on your own?")
                .font(.system(size: 17))
                .foregroundStyle(Color.wwMuted)
                .padding(.top, 10)
                .padding(.bottom, 28)
            Button("Yes, on my own") { answer(true) }.buttonStyle(PrimaryButtonStyle())
            Button("Someone woke me up") { answer(false) }.buttonStyle(SecondaryButtonStyle()).padding(.top, 10)
        }
    }

    @ViewBuilder private var celebration: some View {
        let kept = !session.isTest && (store.entry(for: session.alarmAt)?.wokeOnTime ?? false)
        VStack(spacing: 0) {
            if session.isTest {
                LunaView(streak: 1, size: 120)
                Text("Test complete").font(.rounded(30, .heavy)).foregroundStyle(Color.wwMoon).padding(.top, 18)
                detail("That's how mornings will go. Nothing was logged.")
            } else if kept {
                CelebratingStreak(lunaSize: 120) { luna, number in
                    VStack(spacing: 18) {
                        luna
                        HStack(spacing: 8) {
                            number
                            Text("night streak!")
                        }
                        .font(.rounded(30, .heavy))
                        .foregroundStyle(Color.wwMoon)
                    }
                }
                detail(store.streak >= 7 ? "A whole week. Luna is glowing!" : "Luna is proud of you. Same time tonight?")
            } else {
                LunaView(streak: 0, size: 120)
                Text("Fresh start").font(.rounded(30, .heavy)).foregroundStyle(Color.wwMoon).padding(.top, 18)
                detail("This one didn't count, but tonight is a new chance to start a streak.")
                    .onAppear { store.seenStreak = store.streak }
            }
            Button("Continue") { store.morning = nil }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17))
            .foregroundStyle(Color.wwMuted)
            .padding(.top, 10)
            .padding(.bottom, 28)
    }

    private func answer(_ ownWake: Bool) {
        store.checkIn(ownWake: ownWake)
        withAnimation(.easeOut(duration: 0.35)) { answered = true }
    }
}
