import SwiftUI

@main
struct WakeyWakeyApp: App {
    @State private var store = AppStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Top up the next two weeks of alarms, and fill in nights from Health,
                    // whenever the app opens.
                    guard phase == .active else { return }
                    store.syncAlarms()
                    Task { await store.importFromHealth() }
                }
        }
    }
}

enum Tab: CaseIterable {
    case schedule, alarm, progress
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = Tab.alarm
    @State private var showSettings = false
    @State private var showNight = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            VStack(spacing: 0) {
                header
                ZStack {
                    switch tab {
                    case .alarm: HomeView(tab: $tab, showNight: $showNight)
                    case .schedule: ScheduleView()
                    case .progress: ProgressScreen(openSettings: { showSettings = true })
                    }
                }
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { TabBar(tab: $tab) }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
        }
        .tint(.wwAccent)
        .fullScreenCover(isPresented: $showNight) { NightView() }
        .fullScreenCover(item: $store.morning) { session in
            MorningView(session: session)
        }
    }

    private var header: some View {
        ZStack {
            LogoView()
            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.wwMuted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

/// A faint glow at the top, like the sky just before sunrise.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.wwBackground
            RadialGradient(colors: [.wwAccent.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
                .offset(y: -60)
        }
        .ignoresSafeArea()
    }
}

/// Schedule | Alarm (center, raised circle) | Progress.
struct TabBar: View {
    @Binding var tab: Tab

    var body: some View {
        HStack(alignment: .bottom) {
            item(.schedule, "Schedule", "calendar")
            mainItem
            item(.progress, "Progress", "chart.bar")
        }
        .padding(.top, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(hex: 0x161720, opacity: 0.6))
                .overlay(alignment: .top) { Rectangle().fill(Color.wwBorder).frame(height: 1) }
                .ignoresSafeArea()
        }
    }

    private func item(_ value: Tab, _ title: String, _ icon: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { tab = value }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tab == value ? Color.wwAccent : Color.wwMuted)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    private var mainItem: some View {
        let selected = tab == .alarm
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { tab = .alarm }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "alarm")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(selected ? Color.wwAccentText : Color.wwAccent)
                    .frame(width: 58, height: 58)
                    .background {
                        Circle()
                            .fill(selected ? AnyShapeStyle(.wwPrimary) : AnyShapeStyle(Color.wwSurface2))
                            .overlay(Circle().strokeBorder(Color.wwBackground, lineWidth: 4))
                            .shadow(color: selected ? .wwAccent.opacity(0.4) : .black.opacity(0.4), radius: 10, y: 6)
                    }
                    .offset(y: -18)
                    .padding(.bottom, -18)
                Text("Alarm")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.wwAccent : Color.wwMuted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Alarm")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
