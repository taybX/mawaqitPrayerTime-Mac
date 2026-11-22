import Foundation
import MawaqitKit
import OSLog

/// The last downloaded timetable. Kept on disk so the app starts instantly and
/// works offline: one download holds a whole year of times.
nonisolated struct CachedMosque: Codable, Sendable {
    var sourceURL: URL
    var fetchedAt: Date
    var mosque: MosqueData
}

struct MosqueStore {
    let fileURL: URL
    private let log = Logger(subsystem: "MawaqitPrayerTime", category: "cache")

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support
            .appending(path: "MawaqitPrayerTime", directoryHint: .isDirectory)
            .appending(path: "mosque.json")
    }

    func load() -> CachedMosque? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(CachedMosque.self, from: data)
        } catch {
            log.error("Ignoring unreadable cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ cached: CachedMosque) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(cached).write(to: fileURL, options: .atomic)
        } catch {
            // Not fatal: the app just downloads the timetable again next launch.
            log.error("Couldn't save cache: \(error.localizedDescription, privacy: .public)")
        }
    }
}
