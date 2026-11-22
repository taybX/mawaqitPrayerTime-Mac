import Foundation

/// One entry in a day's timetable.
public struct PrayerTime: Sendable, Hashable, Identifiable {
    public let prayer: Prayer
    public let adhan: Date
    /// Nil when the mosque doesn't publish iqama times, and always nil for Shuruq.
    public let iqama: Date?

    public var id: Date { adhan }

    public init(prayer: Prayer, adhan: Date, iqama: Date?) {
        self.prayer = prayer
        self.adhan = adhan
        self.iqama = iqama
    }
}

/// The timetable for one calendar day at the mosque.
public struct DaySchedule: Sendable, Equatable {
    /// Midnight at the start of the day, in the mosque's time zone.
    public let day: Date
    /// All six entries, Fajr to Isha.
    public let times: [PrayerTime]
    public let isFriday: Bool
    /// Jumu'a times. Only filled on Fridays.
    public let jumua: [Date]

    public func time(for prayer: Prayer) -> PrayerTime? {
        times.first { $0.prayer == prayer }
    }
}

/// Answers "what are today's times" and "what's next" from a mosque's yearly calendar.
public struct PrayerSchedule: Sendable {
    public let mosque: MosqueData
    /// The mosque's time zone. Mawaqit's times are wall-clock times there.
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(mosque: MosqueData, fallbackTimeZone: TimeZone = .current) {
        self.mosque = mosque
        let zone = mosque.timezone.flatMap(TimeZone.init(identifier:)) ?? fallbackTimeZone
        timeZone = zone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        self.calendar = calendar
    }

    /// Midnight at the start of the mosque-local day containing `date`.
    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// The timetable for the mosque-local day containing `date`, or nil if the
    /// mosque's calendar has no entry for it.
    public func day(containing date: Date) -> DaySchedule? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return makeDay(year: year, month: month, day: day)
    }

    /// The first prayer whose adhan comes after `date`, looking into tomorrow if needed.
    public func nextPrayer(after date: Date, includeShuruq: Bool = false) -> PrayerTime? {
        upcomingTimes(after: date, days: 2, includeShuruq: includeShuruq).first
    }

    /// The prayer whose time it currently is: the latest adhan at or before `date`.
    public func currentPrayer(at date: Date) -> PrayerTime? {
        (-1...0)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: date).flatMap(day(containing:)) }
            .flatMap(\.times)
            .filter { $0.prayer.isPrayer && $0.adhan <= date }
            .max { $0.adhan < $1.adhan }
    }

    /// Every prayer after `date` in today plus the following `days - 1` days, in order.
    public func upcomingTimes(after date: Date, days: Int, includeShuruq: Bool = false) -> [PrayerTime] {
        // Start from yesterday: at high latitudes Isha can fall after midnight.
        (-1..<max(days, 1))
            .compactMap { calendar.date(byAdding: .day, value: $0, to: date).flatMap(day(containing:)) }
            .flatMap(\.times)
            .filter { $0.adhan > date && (includeShuruq || $0.prayer.isPrayer) }
            .sorted { $0.adhan < $1.adhan }
    }

    /// The Hijri (Umm al-Qura) date, shifted by the mosque's own adjustment.
    public func hijriDate(for date: Date, locale: Locale = Locale(identifier: "en")) -> String {
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = timeZone
        let adjusted = islamic.date(byAdding: .day, value: mosque.hijriAdjustment, to: date) ?? date
        let formatter = DateFormatter()
        formatter.calendar = islamic
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMMM y"
        return formatter.string(from: adjusted)
    }

    // MARK: - Building a day

    private func makeDay(year: Int, month: Int, day: Int) -> DaySchedule? {
        let key = String(day)
        guard
            mosque.calendar.indices.contains(month - 1),
            let raw = mosque.calendar[month - 1][key], raw.count >= Prayer.allCases.count,
            let midnight = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }

        let iqamaRaw: [String]? =
            mosque.iqamaEnabled && mosque.iqamaCalendar.indices.contains(month - 1)
            ? mosque.iqamaCalendar[month - 1][key]
            : nil

        var times: [PrayerTime] = []
        var previous: Date?
        for prayer in Prayer.allCases {
            guard var adhan = clockTime(raw[prayer.rawValue], on: midnight) else { return nil }
            // Times only move forward through the day; a smaller one (Isha at 00:20) is after midnight.
            if let previous, adhan < previous {
                adhan = calendar.date(byAdding: .day, value: 1, to: adhan) ?? adhan
            }
            previous = adhan

            var iqama: Date?
            if let index = prayer.iqamaIndex, let entries = iqamaRaw, entries.indices.contains(index) {
                iqama = iqamaTime(entries[index], adhan: adhan, midnight: midnight)
            }
            times.append(PrayerTime(prayer: prayer, adhan: adhan, iqama: iqama))
        }

        let isFriday = calendar.component(.weekday, from: midnight) == 6
        let jumua = isFriday
            ? [mosque.jumua, mosque.jumua2, mosque.jumua3].compactMap { $0.flatMap { clockTime($0, on: midnight) } }
            : []
        return DaySchedule(day: midnight, times: times, isFriday: isFriday, jumua: jumua)
    }

    /// Parses "HH:mm" as a wall-clock time on the given mosque-local day.
    func clockTime(_ text: String, on midnight: Date) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard
            parts.count >= 2,
            let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0...24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: midnight)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// Mawaqit iqama entries are either a delay ("+10", "10") or a fixed time ("13:30").
    func iqamaTime(_ text: String, adhan: Date, midnight: Date) -> Date? {
        let entry = text.trimmingCharacters(in: .whitespaces)
        guard !entry.isEmpty else { return nil }

        if entry.contains(":") {
            guard let fixed = clockTime(entry, on: midnight) else { return nil }
            if fixed >= adhan { return fixed }
            // Earlier than the adhan: either past midnight (Isha iqama 00:10) or a
            // timetable mistake. An iqama never comes before its adhan.
            let gap = adhan.timeIntervalSince(fixed)
            return gap > 12 * 3600 ? calendar.date(byAdding: .day, value: 1, to: fixed) : adhan
        }

        let digits = entry.hasPrefix("+") ? String(entry.dropFirst()) : entry
        guard let minutes = Int(digits), minutes >= 0 else { return nil }
        return adhan.addingTimeInterval(TimeInterval(minutes * 60))
    }
}
