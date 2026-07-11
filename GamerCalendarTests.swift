import Testing
import Foundation
import CoreSpotlight
@testable import Gamer_s_Calendar

/// Тесты маппинга ответов IGDB в модели приложения.
struct IGDBMappingTests {

    private let service = IGDBService()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("Игра IGDB превращается в модель приложения")
    func mapsGameToStorage() throws {
        let json = """
        [{
            "id": 42,
            "name": "Test Game",
            "first_release_date": 1751846400,
            "cover": {"image_id": "co42"},
            "screenshots": [{"image_id": "sc42"}],
            "platforms": [
                {"id": 6, "name": "PC (Microsoft Windows)"},
                {"id": 48, "name": "PlayStation 4", "platform_family": 1}
            ]
        }]
        """
        let game = try #require(try decoder.decode([IGDBGame].self, from: Data(json.utf8)).first)
        let storage = service.gamesStorage(from: game)

        #expect(storage.id == 42)
        #expect(storage.gameTitle == "Test Game")
        #expect(storage.releaseDate == Date(timeIntervalSince1970: 1_751_846_400))
        #expect(storage.imageURL?.absoluteString == "https://images.igdb.com/igdb/image/upload/t_720p/sc42.jpg")
        #expect(storage.platforms == "PC (Microsoft Windows), PlayStation 4")
    }

    @Test("Без скриншотов картинкой списка становится обложка")
    func fallsBackToCover() throws {
        let json = """
        [{"id": 1, "name": "Cover Only", "cover": {"image_id": "co1"}}]
        """
        let game = try #require(try decoder.decode([IGDBGame].self, from: Data(json.utf8)).first)
        let storage = service.gamesStorage(from: game)

        #expect(storage.imageURL?.absoluteString == "https://images.igdb.com/igdb/image/upload/t_cover_big/co1.jpg")
        #expect(storage.releaseDate == nil)
        #expect(storage.platformBadges.isEmpty)
    }

    @Test("Платформы сводятся к иконкам без дублей и в стабильном порядке")
    func platformBadges() {
        let platforms = [
            IGDBPlatform(id: 130, name: "Nintendo Switch", platformFamily: 5),
            IGDBPlatform(id: 6, name: "PC (Microsoft Windows)", platformFamily: nil),
            IGDBPlatform(id: 167, name: "PlayStation 5", platformFamily: 1),
            IGDBPlatform(id: 48, name: "PlayStation 4", platformFamily: 1),
            IGDBPlatform(id: 39, name: "iOS", platformFamily: nil),
            IGDBPlatform(id: 9999, name: "Amiga", platformFamily: nil)
        ]

        #expect(service.platformBadges(for: platforms) == [.pc, .playstation, .nintendo, .mobile])
    }

    @Test("Ссылки: только магазины и официальный сайт, магазины первыми")
    func linksFiltering() {
        let websites = [
            IGDBWebsite(url: "https://en.wikipedia.org/wiki/X", type: 3),
            IGDBWebsite(url: "https://example.com", type: 1),
            IGDBWebsite(url: "https://store.steampowered.com/app/1", type: 13),
            IGDBWebsite(url: "https://discord.gg/x", type: 18)
        ]

        let links = service.links(from: websites)

        #expect(links.count == 2)
        #expect(links.first?.title == "Steam")
        #expect(links.last?.url.absoluteString == "https://example.com")
    }

}

/// Тесты группировки игр по месяцам для ленты релизов.
struct MonthGrouperTests {

    @Test("Игры добавляются в секции по месяцам, записи без даты пропускаются")
    func appendsGamesByMonth() {
        var sections: [MonthSection] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let julyFirst = Date(timeIntervalSince1970: 1_751_846_400)
        let julySecond = Date(timeIntervalSince1970: 1_751_932_800)
        let augustFirst = Date(timeIntervalSince1970: 1_754_524_800)

        MonthGrouper.append([
            makeGame(id: 1, releaseDate: julyFirst),
            makeGame(id: 2, releaseDate: nil),
            makeGame(id: 3, releaseDate: julySecond),
            makeGame(id: 4, releaseDate: augustFirst)
        ], to: &sections, calendar: calendar)

        #expect(sections.count == 2)
        #expect(sections[0].games.map(\.id) == [1, 3])
        #expect(sections[1].games.map(\.id) == [4])
    }

    private func makeGame(id: Int, releaseDate: Date?) -> GamesStorage {
        GamesStorage(
            id: id,
            gameTitle: "Game \(id)",
            imageURL: nil,
            releaseDate: releaseDate,
            platforms: "",
            platformBadges: [],
            hypes: nil,
            imageCandidates: nil,
            coverURL: nil,
            artworkURLs: nil
        )
    }

}

/// Тесты обновления сохранённых напоминаний без реальных уведомлений и Spotlight.
struct ReminderServiceTests {

    @Test("При переносе релиза сервис обновляет сохранённую игру и возвращает её id")
    func refreshReleaseDatesUpdatesChangedGames() async throws {
        let defaults = try #require(UserDefaults(suiteName: "ReminderServiceTests.\(UUID().uuidString)"))
        let oldDate = Date(timeIntervalSince1970: 1_751_846_400)
        let newDate = Date(timeIntervalSince1970: 1_754_524_800)
        let oldGame = makeGame(id: 7, title: "Moved Game", releaseDate: oldDate)
        let freshGame = makeGame(id: 7, title: "Moved Game", releaseDate: newDate)

        defaults.set(try JSONEncoder().encode([oldGame]), forKey: "trackedGames")

        let reminderService = ReminderService(
            defaults: defaults,
            schedulesNotifications: false,
            reindexesSpotlight: false
        )
        let changedIDs = await reminderService.refreshReleaseDates(using: MockGameCatalogService(gamesByID: [7: freshGame]))

        #expect(changedIDs == [7])
        #expect(reminderService.trackedGames.map(\.releaseDate) == [newDate])
    }

    private func makeGame(id: Int, title: String, releaseDate: Date?) -> GamesStorage {
        GamesStorage(
            id: id,
            gameTitle: title,
            imageURL: nil,
            releaseDate: releaseDate,
            platforms: "",
            platformBadges: [],
            hypes: nil,
            imageCandidates: nil,
            coverURL: nil,
            artworkURLs: nil
        )
    }

}

/// Тесты чистого парсинга ссылок из виджета и Spotlight.
struct GameDeepLinkTests {

    @Test("URL виджета содержит id игры")
    func parsesWidgetGameURL() throws {
        let url = try #require(URL(string: "gamercalendar://game/42"))

        #expect(GameDeepLink.gameID(from: url) == 42)
    }

    @Test("Некорректные URL игнорируются")
    func rejectsInvalidURLs() throws {
        let wrongHost = try #require(URL(string: "gamercalendar://profile/42"))
        let wrongScheme = try #require(URL(string: "https://game/42"))

        #expect(GameDeepLink.gameID(from: wrongHost) == nil)
        #expect(GameDeepLink.gameID(from: wrongScheme) == nil)
    }

    @Test("Spotlight activity содержит id игры")
    func parsesSpotlightActivity() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "game-99"]

        #expect(GameDeepLink.gameID(from: activity) == 99)
    }

}

private struct MockGameCatalogService: GameCatalogService {

    var gamesByID: [Int: GamesStorage] = [:]

    func fetchGames(page: Int, monthsAhead: Int, search: String?, platform: PlatformFamily?, genre: GenreFilter?, sortByHype: Bool) async throws -> (games: [GamesStorage], hasMore: Bool) {
        ([], false)
    }

    func fetchGames(ids: [Int]) async throws -> [GamesStorage] {
        ids.compactMap { gamesByID[$0] }
    }

    func fetchGames(from startDate: Date, to endDate: Date) async throws -> [GamesStorage] {
        []
    }

    func fetchFranchiseGames(franchiseID: Int) async throws -> [GamesStorage] {
        []
    }

    func fetchGameDetails(id: Int) async throws -> GameDetails {
        GameDetails(
            about: "",
            genres: "",
            developers: "",
            screenshots: [],
            rating: 0,
            ratingsCount: 0,
            trailerURL: nil,
            links: [],
            similarGames: [],
            releaseDates: [],
            releaseAccuracy: .unknown,
            preorderAvailable: false,
            updateBadges: [],
            franchise: nil,
            pageURL: nil
        )
    }

}
