import Foundation

public enum MawaqitError: LocalizedError, Equatable, Sendable {
    case invalidMosqueAddress
    case mosqueNotFound
    case httpStatus(Int)
    case noPrayerData
    case unreadableData(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMosqueAddress:
            "That isn't a Mawaqit mosque link. Paste the address of your mosque's page on mawaqit.net."
        case .mosqueNotFound:
            "Mawaqit has no mosque at that address. Check the link and try again."
        case .httpStatus(let code):
            "Mawaqit answered with an error (HTTP \(code)). Try again later."
        case .noPrayerData:
            "The page loaded, but it had no prayer times in it."
        case .unreadableData(let detail):
            "The prayer times on that page couldn't be read (\(detail))."
        }
    }
}

/// Loads a mosque's timetable from its public page on mawaqit.net.
///
/// Mawaqit's JSON API needs an account token, but every mosque page embeds the
/// same data (a full year of times) for its own JavaScript, so the app reads that.
public struct MawaqitClient: Sendable {
    public static let website = URL(string: "https://mawaqit.net")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Turns whatever the user pasted (a full link, a link without "https://",
    /// a widget or mobile link, or a bare slug) into the mosque's canonical page URL.
    public static func mosquePageURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MawaqitError.invalidMosqueAddress }

        let slug: String
        if trimmed.contains("/") || trimmed.contains(".") {
            let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
            guard
                let components = URLComponents(string: candidate),
                let host = components.host?.lowercased(),
                host == "mawaqit.net" || host.hasSuffix(".mawaqit.net"),
                let last = components.path.split(separator: "/").last
            else { throw MawaqitError.invalidMosqueAddress }
            // Paths look like /en/<slug>, /fr/w/<slug>, /en/m/<slug> or /<slug>.
            slug = String(last)
        } else {
            slug = trimmed
        }

        guard isPlausibleSlug(slug) else { throw MawaqitError.invalidMosqueAddress }
        return website.appending(path: "en").appending(path: slug)
    }

    /// Downloads the mosque page and reads the timetable out of it.
    public func fetchMosque(from pageURL: URL) async throws -> MosqueData {
        var request = URLRequest(url: pageURL, timeoutInterval: 30)
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw MawaqitError.mosqueNotFound }
            guard (200..<300).contains(http.statusCode) else {
                throw MawaqitError.httpStatus(http.statusCode)
            }
        }
        return try MosquePageParser.parse(html: String(decoding: data, as: UTF8.self))
    }

    private static func isPlausibleSlug(_ slug: String) -> Bool {
        // Two-letter paths are language codes ("en", "fr"), not mosques.
        guard slug.count >= 3 else { return false }
        return slug.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        }
    }
}
