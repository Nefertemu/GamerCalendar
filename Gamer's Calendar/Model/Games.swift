
import UIKit

struct GamesStorage {
    let id: Int
    let gameTitle: String
    let imageURL: URL?
    let releaseDate: Date?
    let platforms: String
}

/// Подробности об игре с экрана деталей: описание, жанры, разработчики, скриншоты.
struct GameDetails {
    let about: String
    let genres: String
    let developers: String
    let screenshots: [URL]
    /// Средний рейтинг RAWG по пятибалльной шкале.
    let rating: Double
    let ratingsCount: Int
}

/// Простой кэш загруженных обложек, чтобы не тянуть одну и ту же картинку
/// по сети повторно при переиспользовании ячеек во время скролла.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    /// Сессия с дисковым кэшем: картинки не скачиваются заново после перезапуска.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    private init() {}

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func loadImage(from url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        guard let (data, _) = try? await session.data(from: url),
              let image = UIImage(data: data) else {
            return nil
        }

        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct RawgGamesResponse: Decodable {
    let next: String?
    let results: [RawgGame]
}

struct RawgGame: Decodable {
    let id: Int
    let name: String
    let released: String?
    let backgroundImage: URL?
    let platforms: [RawgPlatformWrapper]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case released
        case backgroundImage = "background_image"
        case platforms
    }
}

struct RawgPlatformWrapper: Decodable {
    let platform: RawgPlatform
}

struct RawgPlatform: Decodable {
    let name: String
}

struct RawgGameDetailResponse: Decodable {
    let descriptionRaw: String?
    let genres: [RawgNamed]?
    let developers: [RawgNamed]?
    let rating: Double?
    let ratingsCount: Int?

    enum CodingKeys: String, CodingKey {
        case descriptionRaw = "description_raw"
        case genres
        case developers
        case rating
        case ratingsCount = "ratings_count"
    }
}

struct RawgNamed: Decodable {
    let name: String
}

struct RawgScreenshotsResponse: Decodable {
    let results: [RawgScreenshot]
}

struct RawgScreenshot: Decodable {
    let image: URL
}

final class RawgService {
    private let apiKey = Secrets.rawgAPIKey

    /// Максимальный размер страницы, разрешённый RAWG API.
    static let pageSize = 40

    func fetchGames(page: Int = 1, yearsAhead: Int = 3, search: String? = nil, parentPlatform: Int? = nil) async throws -> (games: [GamesStorage], hasMore: Bool) {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let today = Date()
        let endDate = Calendar.current.date(byAdding: .year, value: yearsAhead, to: today) ?? today
        let datesRange = "\(dateFormatter.string(from: today)),\(dateFormatter.string(from: endDate))"

        var components = URLComponents(string: "https://api.rawg.io/api/games")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(Self.pageSize)),
            URLQueryItem(name: "dates", value: datesRange),
            URLQueryItem(name: "ordering", value: "released")
        ]

        if let search {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }
        if let parentPlatform {
            components.queryItems?.append(URLQueryItem(name: "parent_platforms", value: String(parentPlatform)))
        }

        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        let response = try JSONDecoder().decode(RawgGamesResponse.self, from: data)

        let games = response.results.compactMap { game -> GamesStorage? in
            guard let released = game.released,
                  let releaseDate = dateFormatter.date(from: released) else {
                return nil
            }

            return GamesStorage(
                id: game.id,
                gameTitle: game.name,
                imageURL: game.backgroundImage,
                releaseDate: releaseDate,
                platforms: game.platforms?
                    .map { $0.platform.name }
                    .joined(separator: ", ") ?? ""
            )
        }

        return (games, response.next != nil)
    }

    func fetchGameDetails(id: Int) async throws -> GameDetails {
        // Описание и скриншоты — разные эндпоинты, грузим параллельно.
        async let detailData = URLSession.shared.data(from: endpointURL(path: "games/\(id)"))
        async let screenshotsData = URLSession.shared.data(from: endpointURL(path: "games/\(id)/screenshots"))

        let detail = try JSONDecoder().decode(RawgGameDetailResponse.self, from: await detailData.0)

        // Скриншоты не критичны: если их не удалось загрузить, показываем остальное.
        let screenshots = (try? JSONDecoder().decode(RawgScreenshotsResponse.self, from: await screenshotsData.0))?
            .results.map(\.image) ?? []

        return GameDetails(
            about: detail.descriptionRaw ?? "",
            genres: detail.genres?.map(\.name).joined(separator: ", ") ?? "",
            developers: detail.developers?.map(\.name).joined(separator: ", ") ?? "",
            screenshots: screenshots,
            rating: detail.rating ?? 0,
            ratingsCount: detail.ratingsCount ?? 0
        )
    }

    private func endpointURL(path: String) -> URL {
        var components = URLComponents(string: "https://api.rawg.io/api/\(path)")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return components.url!
    }
}
