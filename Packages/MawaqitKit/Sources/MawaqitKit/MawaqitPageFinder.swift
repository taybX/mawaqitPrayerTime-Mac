import Foundation

/// A mosque found somewhere other than Mawaqit (for example Apple Maps), which
/// may or may not have a Mawaqit page.
public struct MosqueCandidate: Sendable, Hashable {
    public var name: String
    public var city: String?
    public var latitude: Double
    public var longitude: Double
    /// The mosque's own website, if the map listing has one.
    public var website: URL?

    public init(name: String, city: String? = nil, latitude: Double, longitude: Double, website: URL? = nil) {
        self.name = name
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.website = website
    }
}

/// Finds the Mawaqit page for a mosque found elsewhere, without Mawaqit's private API.
///
/// It tries, in order: a Mawaqit link given as the mosque's website, Mawaqit links
/// or widgets on the mosque's own website, and finally page addresses guessed from
/// the mosque's name. A page only counts if its coordinates are near the mosque,
/// so a common name ("Masjid Al-Fath") can't match a mosque in another city.
public struct MawaqitPageFinder: Sendable {
    private let client: MawaqitClient
    private let session: URLSession

    /// Upper bound on Mawaqit pages downloaded per mosque, to stay polite.
    public static let maxPageChecks = 6
    /// How close a Mawaqit page's coordinates must be to the mosque.
    public static let matchRadius: Double = 2_000

    public init(session: URLSession = .shared) {
        self.session = session
        client = MawaqitClient(session: session)
    }

    public struct Match: Sendable {
        public let pageURL: URL
        public let mosque: MosqueData
    }

    public func findPage(for candidate: MosqueCandidate) async -> Match? {
        var checked: Set<String> = []
        for slug in await candidateSlugs(for: candidate) where checked.count < Self.maxPageChecks {
            guard checked.insert(slug.lowercased()).inserted,
                  let url = try? MawaqitClient.mosquePageURL(from: slug),
                  let mosque = try? await client.fetchMosque(from: url)
            else { continue }
            if Self.isNear(candidate, mosque) {
                return Match(pageURL: url, mosque: mosque)
            }
        }
        return nil
    }

    /// Slugs to try, best evidence first.
    func candidateSlugs(for candidate: MosqueCandidate) async -> [String] {
        var slugs: [String] = []
        if let website = candidate.website {
            if Self.isMawaqitHost(website.host) {
                slugs += Self.mawaqitSlugs(in: website.absoluteString)
            } else if let html = await fetchHomepage(website) {
                slugs += Self.mawaqitSlugs(in: html)
            }
        }
        slugs += Self.slugGuesses(for: candidate)
        return slugs
    }

    private func fetchHomepage(_ url: URL) async -> String? {
        guard let host = url.host?.lowercased(),
              !Self.unfetchableHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              data.count < 3_000_000
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Pure helpers (unit-tested)

    /// Social sites that refuse automated requests, so there's no point asking.
    static let unfetchableHosts = ["facebook.com", "instagram.com", "x.com", "twitter.com", "tiktok.com", "youtube.com"]

    /// Path segments on mawaqit.net that are not mosques.
    static let reservedSegments: Set<String> = [
        "api", "static", "bundles", "images", "img", "uploads", "upload", "css", "js", "assets", "build",
        "media", "fonts", "w", "m", "widget", "login", "register", "mosque", "mosques", "privacy", "terms",
        "faq", "contact", "blog", "news", "app", "download", "backoffice", "cdn", "search", "map",
    ]

    static func isMawaqitHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "mawaqit.net" || host.hasSuffix(".mawaqit.net")
    }

    /// Mosque slugs in mawaqit.net links inside some text (HTML, an iframe, a URL), in order of appearance.
    static func mawaqitSlugs(in text: String) -> [String] {
        let pattern = #"(?i)(?<![a-z0-9-])(?:www\.)?mawaqit\.net/(?:[a-z]{2}/)?(?:(?:w|m|widget)/)?([a-z0-9_-]{3,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen: Set<String> = []
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let slug = String(text[range])
            let key = slug.lowercased()
            guard !reservedSegments.contains(key), seen.insert(key).inserted else { return nil }
            return slug
        }
    }

    /// Lowercase ASCII words joined by hyphens: "Grande Mosquée de Paris" → "grande-mosquee-de-paris".
    static func slugify(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
        var slug = ""
        var pendingHyphen = false
        for scalar in folded.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen, !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        return slug
    }

    /// Mawaqit slugs are usually made from the mosque's name, sometimes with the city added.
    static func slugGuesses(for candidate: MosqueCandidate) -> [String] {
        let name = slugify(candidate.name)
        let city = candidate.city.map(slugify) ?? ""
        let withoutPrefix = name.replacingOccurrences(
            of: #"^(stichting|association|vereniging|centre|center|islamitische-stichting)-"#,
            with: "", options: .regularExpression
        )
        var guesses = [name, withoutPrefix]
        if !city.isEmpty {
            for base in [name, withoutPrefix] where !base.contains(city) {
                guesses.append("\(base)-\(city)")
            }
        }
        var seen: Set<String> = []
        return guesses.filter { $0.count >= 3 && seen.insert($0).inserted }
    }

    static func isNear(_ candidate: MosqueCandidate, _ mosque: MosqueData) -> Bool {
        guard let latitude = mosque.latitude, let longitude = mosque.longitude else { return false }
        return distance(candidate.latitude, candidate.longitude, latitude, longitude) <= matchRadius
    }

    /// Great-circle distance in metres.
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians, dLon = (lon2 - lon1) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
