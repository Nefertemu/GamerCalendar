
import UIKit

struct GamesStorage {
    let gameTitle: String
    let imageURL: URL?
    let releaseDate: Date?
    let platforms: String
}

struct RawgGamesResponse: Decodable {
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

    func fetchGames() async throws -> [GamesStorage] {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let today = Date()
        let twoYearsLater = Calendar.current.date(byAdding: .year, value: 2, to: today) ?? today
        let datesRange = "\(dateFormatter.string(from: today)),\(dateFormatter.string(from: twoYearsLater))"

        var components = URLComponents(string: "https://api.rawg.io/api/games")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "page_size", value: "40"),
            URLQueryItem(name: "dates", value: datesRange),
            URLQueryItem(name: "ordering", value: "released")
        ]

        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        let response = try JSONDecoder().decode(RawgGamesResponse.self, from: data)

        return response.results.compactMap { game in
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
    }
}
