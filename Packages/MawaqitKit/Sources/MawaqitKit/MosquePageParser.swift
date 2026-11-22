import Foundation

/// Extracts the `confData = {...}` object that every Mawaqit mosque page embeds.
public enum MosquePageParser {
    public static func parse(html: String) throws -> MosqueData {
        guard let json = extractConfData(from: html) else { throw MawaqitError.noPrayerData }
        let mosque: MosqueData
        do {
            mosque = try JSONDecoder().decode(MosqueData.self, from: Data(json.utf8))
        } catch let error as DecodingError {
            throw MawaqitError.unreadableData(describe(error))
        }
        guard mosque.calendar.count == 12 else { throw MawaqitError.noPrayerData }
        return mosque
    }

    /// Returns the JSON text of the `confData` object, or nil if the page has none.
    ///
    /// The object is found by matching braces rather than with a regular expression,
    /// so braces and quotes inside JSON strings (announcements, hadith) don't cut it short.
    static func extractConfData(from html: String) -> String? {
        guard let match = html.range(of: #"confData\s*=\s*\{"#, options: .regularExpression) else {
            return nil
        }
        let start = html.index(before: match.upperBound)  // the opening brace
        let bytes = html.utf8[start...]

        var depth = 0
        var inString = false
        var escaped = false
        for index in bytes.indices {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"):
                depth += 1
            case UInt8(ascii: "}"):
                depth -= 1
                if depth == 0 {
                    return String(html.utf8[start...index])
                }
            default:
                break
            }
        }
        return nil
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            "missing \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            context.codingPath.map(\.stringValue).joined(separator: ".").ifEmpty("invalid JSON")
        @unknown default:
            "unknown format"
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
