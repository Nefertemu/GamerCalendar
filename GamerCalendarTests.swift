
import Testing
import Foundation
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
        #expect(storage.imageURL?.absoluteString == "https://images.igdb.com/igdb/image/upload/t_screenshot_big/sc42.jpg")
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
