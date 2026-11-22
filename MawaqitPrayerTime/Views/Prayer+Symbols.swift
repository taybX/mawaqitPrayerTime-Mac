import MawaqitKit

extension Prayer {
    /// SF Symbol that follows the sun through the day.
    var symbolName: String {
        switch self {
        case .fajr: "moon.stars"
        case .shuruq: "sunrise"
        case .dhuhr: "sun.max"
        case .asr: "sun.min"
        case .maghrib: "sunset"
        case .isha: "moon"
        }
    }
}
