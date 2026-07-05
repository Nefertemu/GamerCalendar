
import UIKit

struct GamesStorage {
    let gameTitle: String
    let imageURL: URL?
    let releaseDate: Date?
    let platforms: String
}

/// Простой кэш загруженных обложек, чтобы не тянуть одну и ту же картинку
/// по сети повторно при переиспользовании ячеек во время скролла.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {}

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func loadImage(from url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
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
    let name: String
    let released: String?
    let backgroundImage: URL?
    let platforms: [RawgPlatformWrapper]?

    enum CodingKeys: String, CodingKey {
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

final class RawgService {
    private let apiKey = "f07deefc2bc44d598924364d1352b9db"

    /// Максимальный размер страницы, разрешённый RAWG API.
    static let pageSize = 40

    func fetchGames(page: Int = 1) async throws -> (games: [GamesStorage], hasMore: Bool) {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let today = Date()
        let threeYearsLater = Calendar.current.date(byAdding: .year, value: 3, to: today) ?? today
        let datesRange = "\(dateFormatter.string(from: today)),\(dateFormatter.string(from: threeYearsLater))"

        var components = URLComponents(string: "https://api.rawg.io/api/games")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(Self.pageSize)),
            URLQueryItem(name: "dates", value: datesRange),
            URLQueryItem(name: "ordering", value: "released")
        ]

        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        let response = try JSONDecoder().decode(RawgGamesResponse.self, from: data)

        let games = response.results.compactMap { game -> GamesStorage? in
            guard let released = game.released,
                  let releaseDate = dateFormatter.date(from: released) else {
                return nil
            }

            return GamesStorage(
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
}
