import AppKit
import MawaqitKit
import SwiftUI

/// Today's times for the chosen mosque, with a live countdown to the next prayer.
struct TimetableView: View {
    @Environment(AppModel.self) private var model
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let next = model.nextPrayer {
                NextPrayerCard(next: next)
                Divider()
            }
            if let today = model.today {
                timetable(today)
            } else {
                Text("This mosque's calendar has no times for today.")
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.mosqueName)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(model.gregorianDate) · \(model.hijriDate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.refresh() }
            } label: {
                Group {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 18, height: 18)
            }
            .disabled(model.isLoading)
            .help("Reload times from Mawaqit")

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
            }
            .help("Settings")
        }
        .buttonStyle(.borderless)
        .padding(14)
    }

    private func timetable(_ day: DaySchedule) -> some View {
        let next = model.nextPrayer
        let showIqama = day.times.contains { $0.iqama != nil }
        let columnWidth: CGFloat = model.use24HourClock ? 52 : 72

        return VStack(spacing: 2) {
            HStack(spacing: 8) {
                Spacer()
                Text("Adhan").frame(width: columnWidth, alignment: .trailing)
                if showIqama {
                    Text("Iqama").frame(width: columnWidth, alignment: .trailing)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)

            ForEach(day.times) { entry in
                PrayerRow(
                    entry: entry,
                    isNext: entry == next,
                    isPast: entry.adhan <= model.now,
                    showIqama: showIqama,
                    columnWidth: columnWidth
                )
            }

            if day.isFriday, !day.jumua.isEmpty {
                JumuaRow(times: day.jumua)
            }
        }
        .padding(10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let error = model.errorMessage {
                ErrorText(error)
                    .lineLimit(2)
                    .help(error)
            } else if let updated = model.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
            }
            Spacer(minLength: 0)
            if let url = model.mosquePageURL {
                Link("Mawaqit page", destination: url)
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct NextPrayerCard: View {
    @Environment(AppModel.self) private var model
    let next: PrayerTime

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next prayer")
                .font(.caption.weight(.medium))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(next.prayer.name)
                    .font(.title2.weight(.semibold))
                Text(next.prayer.arabicName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                // Spelled out ("in 18m 28s") so it can't be mistaken for a clock time.
                Text("in \(AppModel.preciseCountdown(from: model.now, to: next.adhan))")
                    .font(.title3.weight(.medium).monospacedDigit())
                    .foregroundStyle(.tint)
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var detail: String {
        var text = "Adhan \(model.time(next.adhan))"
        if let iqama = next.iqama {
            text += " · Iqama \(model.time(iqama))"
        }
        return text
    }
}

private struct PrayerRow: View {
    @Environment(AppModel.self) private var model
    let entry: PrayerTime
    let isNext: Bool
    let isPast: Bool
    let showIqama: Bool
    let columnWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.prayer.symbolName)
                .frame(width: 18)
                .foregroundStyle(isNext ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(entry.prayer.name)
                .fontWeight(isNext ? .semibold : .regular)
            Text(entry.prayer.arabicName)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(model.time(entry.adhan))
                .monospacedDigit()
                .fontWeight(isNext ? .semibold : .regular)
                .frame(width: columnWidth, alignment: .trailing)
            if showIqama {
                Text(entry.iqama.map { model.time($0) } ?? "–")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth, alignment: .trailing)
            }
        }
        .foregroundStyle(entry.prayer.isPrayer ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
        .opacity(isPast && !isNext ? 0.5 : 1)
    }
}

private struct JumuaRow: View {
    @Environment(AppModel.self) private var model
    let times: [Date]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.3")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text("Jumu'a")
            Text("الجمعة")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(times.map { model.time($0) }.joined(separator: " · "))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
