import Foundation
import Testing
@testable import MawaqitKit

// All fixtures are synthetic: a made-up mosque in Amsterdam with the same
// timetable every day, which keeps expected values easy to read.

private let dailyTimes = ["06:30", "08:10", "12:40", "14:40", "17:00", "18:30"]
private let dailyIqama = ["+10", "13:15", "+5", "+0", "+10"]

private func confJSON(
    times: [String] = dailyTimes,
    iqama: [String] = dailyIqama,
    extra: [String: Any] = [:]
) throws -> String {
    let month = Dictionary(uniqueKeysWithValues: (1...31).map { (String($0), times) })
    let iqamaMonth = Dictionary(uniqueKeysWithValues: (1...31).map { (String($0), iqama) })
    var conf: [String: Any] = [
        "name": "Test Mosque",
        "timezone": "Europe/Amsterdam",
        "latitude": 52.37,
        "longitude": "4.89",
        "calendar": Array(repeating: month, count: 12),
        "iqamaCalendar": Array(repeating: iqamaMonth, count: 12),
        "iqamaEnabled": true,
        "jumua": "13:30",
        "jumua2": "14:15",
        "jumua3": NSNull(),
        "hijriAdjustment": "-1",
        "announcements": [["title": "Eid {party}", "content": "Say \"salam\" } and bring food"]],
    ]
    conf.merge(extra) { _, new in new }
    let data = try JSONSerialization.data(withJSONObject: conf, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func page(_ json: String) -> String {
    """
    <html><head><script>
        var something = {"a": 1};
        var confData = \(json);
        var after = {"b": "}"};
    </script></head><body>Mosque</body></html>
    """
}

private func makeSchedule(times: [String] = dailyTimes, iqama: [String] = dailyIqama) throws -> PrayerSchedule {
    PrayerSchedule(mosque: try MosquePageParser.parse(html: page(confJSON(times: times, iqama: iqama))))
}

private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

/// A wall-clock moment in Amsterdam.
private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = amsterdam
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Page parsing")
struct PageParsingTests {
    @Test func extractsConfDataDespiteBracesAndQuotesInStrings() throws {
        let json = try confJSON()
        #expect(MosquePageParser.extractConfData(from: page(json)) == json)
    }

    @Test func decodesFieldsLeniently() throws {
        let mosque = try MosquePageParser.parse(html: page(confJSON()))
        #expect(mosque.name == "Test Mosque")
        #expect(mosque.timezone == "Europe/Amsterdam")
        #expect(mosque.longitude == 4.89)  // sent as a string
        #expect(mosque.hijriAdjustment == -1)  // sent as a string
        #expect(mosque.jumua == "13:30")
        #expect(mosque.jumua3 == nil)
        #expect(mosque.calendar.count == 12)
    }

    @Test func fallsBackToLabelWhenNameIsMissing() throws {
        let json = try confJSON(extra: ["name": NSNull(), "label": "Label Mosque"])
        #expect(try MosquePageParser.parse(html: page(json)).name == "Label Mosque")
    }

    @Test func pageWithoutConfDataThrows() {
        #expect(throws: MawaqitError.noPrayerData) {
            try MosquePageParser.parse(html: "<html><body>Not a mosque</body></html>")
        }
    }

    @Test func pageWithoutCalendarThrowsReadableError() throws {
        let html = page(#"{"name": "No Calendar"}"#)
        #expect(throws: MawaqitError.unreadableData("missing calendar")) {
            try MosquePageParser.parse(html: html)
        }
    }

    @Test func cacheRoundTripKeepsEverything() throws {
        let mosque = try MosquePageParser.parse(html: page(confJSON()))
        let decoded = try JSONDecoder().decode(MosqueData.self, from: JSONEncoder().encode(mosque))
        #expect(decoded == mosque)
    }
}

@Suite("Mosque links")
struct MosqueLinkTests {
    @Test(arguments: [
        "https://mawaqit.net/en/test-mosque",
        "https://mawaqit.net/fr/test-mosque",
        "mawaqit.net/nl/test-mosque",
        "https://mawaqit.net/en/w/test-mosque?showOnly5PrayerTimes=0",
        "https://www.mawaqit.net/en/m/test-mosque/",
        "  test-mosque  ",
    ])
    func normalisesToEnglishPage(input: String) throws {
        #expect(try MawaqitClient.mosquePageURL(from: input).absoluteString == "https://mawaqit.net/en/test-mosque")
    }

    @Test(arguments: [
        "",
        "https://example.com/en/test-mosque",
        "https://mawaqit.net/en/",
        "https://mawaqit.net",
        "not a mosque",
    ])
    func rejectsNonMosqueInput(input: String) {
        #expect(throws: MawaqitError.invalidMosqueAddress) {
            try MawaqitClient.mosquePageURL(from: input)
        }
    }
}

@Suite("Schedule")
struct ScheduleTests {
    @Test func buildsDayInMosqueTimeZone() throws {
        let day = try #require(try makeSchedule().day(containing: local(2026, 11, 22, 10)))
        #expect(day.times.map(\.prayer) == Prayer.allCases)
        #expect(day.time(for: .fajr)?.adhan == local(2026, 11, 22, 6, 30))
        #expect(day.time(for: .isha)?.adhan == local(2026, 11, 22, 18, 30))
        #expect(day.time(for: .shuruq)?.iqama == nil)
    }

    @Test func readsIqamaDelaysAndFixedTimes() throws {
        let day = try #require(try makeSchedule().day(containing: local(2026, 11, 22, 10)))
        #expect(day.time(for: .fajr)?.iqama == local(2026, 11, 22, 6, 40))  // "+10"
        #expect(day.time(for: .dhuhr)?.iqama == local(2026, 11, 22, 13, 15))  // "13:15"
        #expect(day.time(for: .asr)?.iqama == local(2026, 11, 22, 14, 45))  // "+5"
        #expect(day.time(for: .maghrib)?.iqama == local(2026, 11, 22, 17, 0))  // "+0"
    }

    @Test func noIqamaWhenMosqueDisablesIt() throws {
        var mosque = try MosquePageParser.parse(html: page(confJSON()))
        mosque.iqamaEnabled = false
        let day = try #require(PrayerSchedule(mosque: mosque).day(containing: local(2026, 11, 22, 10)))
        #expect(day.times.allSatisfy { $0.iqama == nil })
    }

    @Test func nextPrayerSkipsShuruqAndRollsToTomorrow() throws {
        let schedule = try makeSchedule()
        #expect(schedule.nextPrayer(after: local(2026, 11, 22, 7))?.prayer == .dhuhr)
        #expect(schedule.nextPrayer(after: local(2026, 11, 22, 7), includeShuruq: true)?.prayer == .shuruq)
        let afterIsha = try #require(schedule.nextPrayer(after: local(2026, 11, 22, 21)))
        #expect(afterIsha.prayer == .fajr)
        #expect(afterIsha.adhan == local(2026, 11, 23, 6, 30))
    }

    @Test func currentPrayerIsLatestAdhanSoFar() throws {
        let schedule = try makeSchedule()
        #expect(schedule.currentPrayer(at: local(2026, 11, 22, 15))?.prayer == .asr)
        #expect(schedule.currentPrayer(at: local(2026, 11, 22, 3))?.adhan == local(2026, 11, 21, 18, 30))
    }

    @Test func ishaAfterMidnightBelongsToTheNextMorning() throws {
        let summer = ["03:10", "05:20", "13:45", "18:00", "22:05", "00:20"]
        let day = try #require(try makeSchedule(times: summer).day(containing: local(2026, 6, 20, 12)))
        #expect(day.time(for: .isha)?.adhan == local(2026, 6, 21, 0, 20))
    }

    @Test func fridayHasJumuaTimes() throws {
        let schedule = try makeSchedule()
        let friday = try #require(schedule.day(containing: local(2026, 11, 27, 9)))
        #expect(friday.isFriday)
        #expect(friday.jumua == [local(2026, 11, 27, 13, 30), local(2026, 11, 27, 14, 15)])
        let saturday = try #require(schedule.day(containing: local(2026, 11, 28, 9)))
        #expect(!saturday.isFriday)
        #expect(saturday.jumua.isEmpty)
    }

    @Test func upcomingTimesCoverTwoDaysInOrder() throws {
        let upcoming = try makeSchedule().upcomingTimes(after: local(2026, 11, 22, 13), days: 2)
        #expect(upcoming.map(\.prayer) == [.asr, .maghrib, .isha, .fajr, .dhuhr, .asr, .maghrib, .isha])
        #expect(zip(upcoming, upcoming.dropFirst()).allSatisfy { $0.adhan < $1.adhan })
    }

    @Test func hijriDateAppliesMosqueAdjustment() throws {
        let schedule = try makeSchedule()  // hijriAdjustment is -1
        var plain = schedule.mosque
        plain.hijriAdjustment = 0
        let date = local(2026, 11, 22, 12)
        let adjusted = schedule.hijriDate(for: date)
        let unadjusted = PrayerSchedule(mosque: plain).hijriDate(for: date)
        #expect(adjusted.hasSuffix("1448"))
        #expect(adjusted != unadjusted)
    }
}
