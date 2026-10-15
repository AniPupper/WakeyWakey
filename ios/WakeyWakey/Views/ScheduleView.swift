import SwiftUI

struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var picker

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle("Schedule")
                modePicker
                Group {
                    switch store.schedule.mode {
                    case .everyday:
                        GroupCard(title: "Every day", days: SleepSchedule.allDays)
                    case .weekdays:
                        VStack(spacing: 12) {
                            GroupCard(title: "Monday – Friday", days: SleepSchedule.weekdays)
                            GroupCard(title: "Saturday & Sunday", days: SleepSchedule.weekend, canTurnOff: true)
                        }
                    case .custom:
                        CustomTable()
                    }
                }
                .padding(.top, 16)
                .opacity(store.schedule.enabled ? 1 : 0.45)
                .transition(.opacity.combined(with: .offset(y: 10)))
                .id(store.schedule.mode)

                Text("Bedtime means the night before each wake-up.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wwMuted)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)

                Toggle(isOn: $store.schedule.enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Alarms on").font(.system(size: 17, weight: .semibold))
                        Text("Turn off for vacations without losing your times.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.wwMuted)
                    }
                }
                .padding(16)
                .card()
                .padding(.top, 24)
            }
            .foregroundStyle(Color.wwText)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    /// One-of-three picker: a solid pill slides to the chosen option.
    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(ScheduleMode.allCases) { mode in
                let selected = store.schedule.mode == mode
                Button {
                    guard !selected else { return }
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { store.schedule.switchMode(to: mode) }
                } label: {
                    Text(mode.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Color.wwAccentText : Color.wwMuted)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.wwPrimary)
                                    .shadow(color: .wwAccent.opacity(0.35), radius: 7, y: 4)
                                    .matchedGeometryEffect(id: "pill", in: picker)
                            }
                        }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.wwSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.wwBorder))
    }
}

struct PageTitle: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 32, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A time field for a schedule time.
struct TimeField: View {
    var label: String
    @Binding var time: ClockTime

    var body: some View {
        DatePicker(label, selection: Binding(get: { time.asDate }, set: { time = ClockTime($0) }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .accessibilityLabel(label)
    }
}

/// One card that edits several days at once (all week, Mon–Fri or the weekend).
private struct GroupCard: View {
    var title: String
    var days: [Int]
    var canTurnOff = false
    @Environment(AppStore.self) private var store

    private var first: DayPlan { store.schedule.days[days[0]] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(first.on ? "\(Format.duration(minutes: first.sleepMinutes)) of sleep" : "No alarm")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.wwMuted)
                }
                Spacer()
                if canTurnOff {
                    Toggle("Alarm on \(title)", isOn: binding(\.on)).labelsHidden()
                }
            }
            if first.on {
                HStack(spacing: 10) {
                    field("Bedtime", \.bed)
                    field("Wake up", \.wake)
                }
            }
        }
        .padding(16)
        .card()
    }

    private func field(_ label: String, _ keyPath: WritableKeyPath<DayPlan, ClockTime>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.wwMuted)
            TimeField(label: "\(title) \(label.lowercased())", time: binding(keyPath))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DayPlan, T>) -> Binding<T> {
        Binding(
            get: { store.schedule.days[days[0]][keyPath: keyPath] },
            set: { value in withAnimation { store.schedule.update(days) { $0[keyPath: keyPath] = value } } },
        )
    }
}

/// Custom mode: a compact line per day.
private struct CustomTable: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                Spacer().frame(width: 40)
                Text("Bedtime").frame(maxWidth: .infinity, alignment: .leading)
                Text("Wake up").frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 51)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.wwMuted)
            .padding(.vertical, 8)
            ForEach(SleepSchedule.allDays, id: \.self) { index in
                Divider().overlay(Color.wwBorder)
                HStack(spacing: 6) {
                    Text(SleepSchedule.shortDayNames[index])
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, alignment: .leading)
                    TimeField(label: "\(SleepSchedule.dayNames[index]) bedtime", time: $store.schedule.days[index].bed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TimeField(label: "\(SleepSchedule.dayNames[index]) wake up", time: $store.schedule.days[index].wake)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Alarm on \(SleepSchedule.dayNames[index])", isOn: $store.schedule.days[index].on)
                        .labelsHidden()
                }
                .opacity(store.schedule.days[index].on ? 1 : 0.45)
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .card()
    }
}
