import Foundation

/// The six daily times a Mawaqit timetable lists, in the order Mawaqit stores them.
public enum Prayer: Int, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case fajr, shuruq, dhuhr, asr, maghrib, isha

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .fajr: "Fajr"
        case .shuruq: "Shuruq"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    public var arabicName: String {
        switch self {
        case .fajr: "الفجر"
        case .shuruq: "الشروق"
        case .dhuhr: "الظهر"
        case .asr: "العصر"
        case .maghrib: "المغرب"
        case .isha: "العشاء"
        }
    }

    /// Shuruq (sunrise) appears in the timetable but is not a prayer.
    public var isPrayer: Bool { self != .shuruq }

    /// The five daily prayers, without Shuruq.
    public static let obligatory: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    /// Position in Mawaqit's five-entry iqama arrays, which leave out Shuruq.
    var iqamaIndex: Int? {
        switch self {
        case .fajr: 0
        case .shuruq: nil
        case .dhuhr: 1
        case .asr: 2
        case .maghrib: 3
        case .isha: 4
        }
    }

    public static func < (lhs: Prayer, rhs: Prayer) -> Bool { lhs.rawValue < rhs.rawValue }
}
