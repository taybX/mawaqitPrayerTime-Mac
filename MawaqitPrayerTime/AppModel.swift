import Foundation
import MawaqitKit
import Observation
import ServiceManagement

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case countdown, time, iconOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .countdown: "Countdown"
        case .time: "Prayer time"
        case .iconOnly: "Icon only"
        }
    }
}

/// Everything the menu bar icon and its panel show, plus the user's settings.
@Observable
final class AppModel {
    // MARK: Settings, saved in UserDefaults

    /// The chosen mosque's Mawaqit page. Empty until the user sets one up.
    private(set) var mosqueAddress: String {
        didSet { defaults.set(mosqueAddress, forKey: Keys.mosqueAddress) }
    }

    var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    var use24HourClock: Bool {
        didSet {
            defaults.set(use24HourClock, forKey: Keys.use24HourClock)
            scheduleNotifications()  // their text contains times
        }
    }

    var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            if notificationsEnabled {
                Task {
                    notificationsBlocked = !(await notifier.requestAuthorization())
                    scheduleNotifications()
                }
            } else {
                scheduleNotifications()
            }
        }
    }

    var notifiedPrayers: Set<Prayer> {
        didSet {
            defaults.set(notifiedPrayers.map(\.rawValue).sorted(), forKey: Keys.notifiedPrayers)
            scheduleNotifications()
        }
    }

    /// Minutes before the adhan for an extra reminder; 0 means none.
    var reminderMinutes: Int {
        didSet {
            defaults.set(reminderMinutes, forKey: Keys.reminderMinutes)
            scheduleNotifications()
        }
    }

    /// Backed by the system's login items rather than UserDefaults, so it stays
    /// correct if the user changes it in System Settings.
    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    errorMessage = "Couldn't change Open at Login: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: State

    private(set) var schedule: PrayerSchedule?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var notificationsBlocked = false
    /// Ticks every second; views that read it update with the clock.
    private(set) var now = Date()

    /// "Find mosques near me". Lives here so results survive the panel closing
    /// (for example while the location permission prompt is up).
    let nearby = NearbyMosqueSearch()

    private let defaults: UserDefaults
    private let client = MawaqitClient()
    private let store = MosqueStore()
    private let notifier = PrayerNotifier()

    @ObservationIgnored private var loadedAddress: String?
    @ObservationIgnored private var lastRefreshAttempt: Date?
    @ObservationIgnored private var notifiedDay: Date?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    @ObservationIgnored private let timeFormatter = DateFormatter()

    /// The yearly calendar rarely changes, but mosques do adjust iqama times.
    private static let refreshInterval: TimeInterval = 12 * 3600
    /// How long to wait before retrying a failed automatic refresh.
    private static let retryInterval: TimeInterval = 15 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mosqueAddress = defaults.string(forKey: Keys.mosqueAddress) ?? ""
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .countdown
        use24HourClock = defaults.object(forKey: Keys.use24HourClock) as? Bool ?? true
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        notifiedPrayers = (defaults.array(forKey: Keys.notifiedPrayers) as? [Int])
            .map { Set($0.compactMap(Prayer.init(rawValue:))) } ?? Set(Prayer.obligatory)
        reminderMinutes = defaults.integer(forKey: Keys.reminderMinutes)

        if let cached = store.load() {
            show(cached)
        }
        if notificationsEnabled {
            Task { notificationsBlocked = await notifier.isDenied() }
        }
        startClock()
    }

    // MARK: Derived values for the views

    var today: DaySchedule? { schedule?.day(containing: now) }

    var nextPrayer: PrayerTime? { schedule?.nextPrayer(after: now) }

    var mosqueName: String { schedule?.mosque.name ?? "" }

    var mosquePageURL: URL? { loadedAddress.flatMap(URL.init(string:)) }

    var gregorianDate: String {
        let style = Date.FormatStyle(locale: Locale(identifier: "en_GB"), timeZone: schedule?.timeZone ?? .current)
        return now.formatted(style.weekday(.wide).day().month(.wide))
    }

    var hijriDate: String { schedule?.hijriDate(for: now) ?? "" }

    var menuBarTitle: String {
        guard let next = nextPrayer else { return "" }
        switch menuBarStyle {
        case .countdown: return "\(next.prayer.name) in \(Self.countdown(from: now, to: next.adhan))"
        case .time: return "\(next.prayer.name) \(time(next.adhan))"
        case .iconOnly: return ""
        }
    }

    /// Formats a time in the mosque's time zone with the user's clock preference.
    func time(_ date: Date) -> String {
        let format = use24HourClock ? "HH:mm" : "h:mm a"
        let zone = schedule?.timeZone ?? .current
        if timeFormatter.dateFormat != format || timeFormatter.timeZone != zone {
            timeFormatter.locale = Locale(identifier: "en_US_POSIX")
            timeFormatter.dateFormat = format
            timeFormatter.timeZone = zone
        }
        return timeFormatter.string(from: date)
    }

    /// "1h 5m", "45m"; rounds up so it never shows "0m" before the adhan.
    static func countdown(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "1h 05m", "18m 28s", "9s" for the panel, which redraws every second.
    static func preciseCountdown(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start).rounded(.up)))
        let hours = seconds / 3600, minutes = seconds % 3600 / 60, rest = seconds % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, rest) }
        return "\(rest)s"
    }

    // MARK: Loading

    /// Checks and downloads a mosque, and switches to it if that works.
    @discardableResult
    func selectMosque(address: String) async -> Bool {
        await load(address: address)
    }

    /// Downloads the current mosque's timetable again, keeping the old one on failure.
    func refresh() async {
        guard !mosqueAddress.isEmpty else { return }
        await load(address: mosqueAddress)
    }

    @discardableResult
    private func load(address: String) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        lastRefreshAttempt = .now
        defer { isLoading = false }

        do {
            let url = try MawaqitClient.mosquePageURL(from: address)
            let mosque = try await client.fetchMosque(from: url)
            adopt(CachedMosque(sourceURL: url, fetchedAt: .now, mosque: mosque))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Switches to a mosque the nearby search already downloaded.
    func useFoundMosque(_ match: MawaqitPageFinder.Match) {
        adopt(CachedMosque(sourceURL: match.pageURL, fetchedAt: .now, mosque: match.mosque))
    }

    private func adopt(_ cached: CachedMosque) {
        store.save(cached)
        mosqueAddress = cached.sourceURL.absoluteString
        show(cached)
        errorMessage = nil
    }

    private func show(_ cached: CachedMosque) {
        schedule = PrayerSchedule(mosque: cached.mosque)
        lastUpdated = cached.fetchedAt
        loadedAddress = cached.sourceURL.absoluteString
        notifiedDay = nil  // the next tick reschedules notifications for the new timetable
    }

    private var needsRefresh: Bool {
        guard !mosqueAddress.isEmpty, !isLoading else { return false }
        if let lastRefreshAttempt, now.timeIntervalSince(lastRefreshAttempt) < Self.retryInterval {
            return false
        }
        guard let lastUpdated, loadedAddress == mosqueAddress else { return true }
        return now.timeIntervalSince(lastUpdated) > Self.refreshInterval
    }

    // MARK: Clock

    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                // Wake just after the next whole second so countdowns flip on time.
                let fraction = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .seconds(1 - fraction + 0.01))
            }
        }
    }

    private func tick() {
        now = Date()
        if needsRefresh {
            Task { await refresh() }
        }
        // Notifications cover two days ahead, so top them up once a day (and after a new download).
        if let schedule, notifiedDay != schedule.startOfDay(for: now) {
            notifiedDay = schedule.startOfDay(for: now)
            scheduleNotifications()
        }
    }

    // MARK: Notifications

    private func scheduleNotifications() {
        notificationTask?.cancel()
        let alerts = notificationsEnabled ? upcomingAlerts() : []
        notificationTask = Task { await notifier.replacePending(with: alerts) }
    }

    private func upcomingAlerts() -> [PrayerAlert] {
        guard let schedule else { return [] }
        let start = Date()
        var alerts: [PrayerAlert] = []
        for entry in schedule.upcomingTimes(after: start, days: 2) where notifiedPrayers.contains(entry.prayer) {
            let stamp = Int(entry.adhan.timeIntervalSince1970)
            var body = "Adhan at \(time(entry.adhan))"
            if let iqama = entry.iqama, iqama > entry.adhan {
                body += ", iqama at \(time(iqama))"
            }
            alerts.append(PrayerAlert(
                id: "adhan-\(stamp)",
                date: entry.adhan,
                title: "\(entry.prayer.name) · \(entry.prayer.arabicName)",
                body: "\(body) · \(schedule.mosque.name)"
            ))

            let reminder = entry.adhan.addingTimeInterval(-Double(reminderMinutes) * 60)
            if reminderMinutes > 0, reminder > start {
                alerts.append(PrayerAlert(
                    id: "reminder-\(stamp)",
                    date: reminder,
                    title: "\(entry.prayer.name) in \(reminderMinutes) minutes",
                    body: "Adhan at \(time(entry.adhan)) · \(schedule.mosque.name)"
                ))
            }
        }
        return alerts
    }

    private enum Keys {
        static let mosqueAddress = "mosqueAddress"
        static let menuBarStyle = "menuBarStyle"
        static let use24HourClock = "use24HourClock"
        static let notificationsEnabled = "notificationsEnabled"
        static let notifiedPrayers = "notifiedPrayers"
        static let reminderMinutes = "reminderMinutes"
    }
}
