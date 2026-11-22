import Foundation
import Testing
@testable import MawaqitKit

@Suite("Finding Mawaqit pages")
struct PageFinderTests {
    @Test(arguments: [
        ("Grande Mosquée de Paris", "grande-mosquee-de-paris"),
        ("Moskee Al-Kabir", "moskee-al-kabir"),
        ("  Masjid   An-Nour (Centrum) ", "masjid-an-nour-centrum"),
        ("Mosquée Adda’wa", "mosquee-adda-wa"),
    ])
    func slugify(name: String, expected: String) {
        #expect(MawaqitPageFinder.slugify(name) == expected)
    }

    @Test func findsSlugsInLinksAndWidgets() {
        let html = """
        <a href="https://mawaqit.net/fr/mosquee-exemple-lyon">Horaires</a>
        <iframe src="https://mawaqit.net/en/w/masjid-test-1012ab?showOnly5PrayerTimes=0"></iframe>
        <img src="https://cdn.mawaqit.net/images/logo.png">
        <a href="https://MAWAQIT.net/fr/mosquee-exemple-lyon">again</a>
        <a href="https://notmawaqit.net/fr/other-site">nope</a>
        <a href="https://mawaqit.net/en/m/mobile-mosque">mobile</a>
        """
        #expect(MawaqitPageFinder.mawaqitSlugs(in: html) == ["mosquee-exemple-lyon", "masjid-test-1012ab", "mobile-mosque"])
    }

    @Test func guessesFromNameAndCity() {
        let candidate = MosqueCandidate(name: "Stichting Moskee Sonat", city: "Amsterdam", latitude: 0, longitude: 0)
        #expect(MawaqitPageFinder.slugGuesses(for: candidate) == [
            "stichting-moskee-sonat", "moskee-sonat", "stichting-moskee-sonat-amsterdam", "moskee-sonat-amsterdam",
        ])
    }

    @Test func doesNotRepeatCityAlreadyInName() {
        let candidate = MosqueCandidate(name: "Grande Mosquée de Paris", city: "Paris", latitude: 0, longitude: 0)
        #expect(MawaqitPageFinder.slugGuesses(for: candidate) == ["grande-mosquee-de-paris"])
    }

    @Test func matchesOnlyNearbyPages() {
        let candidate = MosqueCandidate(name: "Test", latitude: 52.3676, longitude: 4.9041)
        var mosque = MosqueData(name: "Test", calendar: [])
        mosque.latitude = 52.3700
        mosque.longitude = 4.9100  // about 500 m away
        #expect(MawaqitPageFinder.isNear(candidate, mosque))
        mosque.latitude = 48.8566
        mosque.longitude = 2.3522  // Paris
        #expect(!MawaqitPageFinder.isNear(candidate, mosque))
        mosque.latitude = nil
        #expect(!MawaqitPageFinder.isNear(candidate, mosque))
    }

    @Test func distanceIsInMetres() {
        // Amsterdam to Paris is roughly 430 km.
        let metres = MawaqitPageFinder.distance(52.3676, 4.9041, 48.8566, 2.3522)
        #expect((420_000...440_000).contains(metres))
    }
}
