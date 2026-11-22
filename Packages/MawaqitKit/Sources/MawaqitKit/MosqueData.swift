import Foundation

/// The part of a Mawaqit mosque page's `confData` object that the app uses.
///
/// Mawaqit publishes a whole year of times on each mosque page, so one download
/// keeps the app working offline until the mosque changes its timetable.
public struct MosqueData: Codable, Sendable, Equatable {
    public var name: String
    /// IANA identifier such as "Europe/Amsterdam". Mawaqit times are wall-clock times in this zone.
    public var timezone: String?
    public var latitude: Double?
    public var longitude: Double?
    public var url: String?
    /// Twelve months. Each maps a day number ("1"..."31") to six "HH:mm" times:
    /// Fajr, Shuruq, Dhuhr, Asr, Maghrib, Isha.
    public var calendar: [[String: [String]]]
    /// Twelve months. Each maps a day number to five iqama entries (no Shuruq),
    /// either a delay after the adhan ("+10") or a fixed time ("13:30").
    public var iqamaCalendar: [[String: [String]]]
    public var iqamaEnabled: Bool
    public var jumua: String?
    public var jumua2: String?
    public var jumua3: String?
    /// Days to add to the computed Hijri date, as set by the mosque.
    public var hijriAdjustment: Int

    public init(
        name: String,
        timezone: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        url: String? = nil,
        calendar: [[String: [String]]],
        iqamaCalendar: [[String: [String]]] = [],
        iqamaEnabled: Bool = true,
        jumua: String? = nil,
        jumua2: String? = nil,
        jumua3: String? = nil,
        hijriAdjustment: Int = 0
    ) {
        self.name = name
        self.timezone = timezone
        self.latitude = latitude
        self.longitude = longitude
        self.url = url
        self.calendar = calendar
        self.iqamaCalendar = iqamaCalendar
        self.iqamaEnabled = iqamaEnabled
        self.jumua = jumua
        self.jumua2 = jumua2
        self.jumua3 = jumua3
        self.hijriAdjustment = hijriAdjustment
    }

    private enum CodingKeys: String, CodingKey {
        case name, label, timezone, latitude, longitude, url
        case calendar, iqamaCalendar, iqamaEnabled
        case jumua, jumua2, jumua3, hijriAdjustment
    }

    /// Decodes both Mawaqit's page data and the app's own cache. Mawaqit's field
    /// types are not always consistent (numbers sometimes arrive as strings), so
    /// everything except the timetable is read leniently.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = c.lenientString(.name) ?? c.lenientString(.label)
        self.name = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Mosque"
        timezone = c.lenientString(.timezone)
        latitude = c.lenientDouble(.latitude)
        longitude = c.lenientDouble(.longitude)
        url = c.lenientString(.url)
        calendar = try c.decode([[String: [String]]].self, forKey: .calendar)
        iqamaCalendar = (try? c.decode([[String: [String]]].self, forKey: .iqamaCalendar)) ?? []
        iqamaEnabled = c.lenientBool(.iqamaEnabled) ?? true
        jumua = c.lenientString(.jumua)
        jumua2 = c.lenientString(.jumua2)
        jumua3 = c.lenientString(.jumua3)
        hijriAdjustment = c.lenientInt(.hijriAdjustment) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(timezone, forKey: .timezone)
        try c.encodeIfPresent(latitude, forKey: .latitude)
        try c.encodeIfPresent(longitude, forKey: .longitude)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encode(calendar, forKey: .calendar)
        try c.encode(iqamaCalendar, forKey: .iqamaCalendar)
        try c.encode(iqamaEnabled, forKey: .iqamaEnabled)
        try c.encodeIfPresent(jumua, forKey: .jumua)
        try c.encodeIfPresent(jumua2, forKey: .jumua2)
        try c.encodeIfPresent(jumua3, forKey: .jumua3)
        try c.encode(hijriAdjustment, forKey: .hijriAdjustment)
    }
}

private extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return nil
    }
}
