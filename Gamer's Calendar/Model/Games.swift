
import UIKit

struct GamesStorage: Codable {
    let id: Int
    let gameTitle: String
    let imageURL: URL?
    let releaseDate: Date?
    /// Полные названия платформ для экрана деталей.
    let platforms: String
    /// Иконки платформ для ячейки списка.
    let platformBadges: [PlatformBadge]
}

/// Платформа в виде иконки SF Symbols для ячейки списка.
enum PlatformBadge: String, Codable, CaseIterable {
    case pc
    case playstation
    case xbox
    case nintendo
    case mobile

    var symbolName: String {
        switch self {
        case .pc: return "desktopcomputer"
        case .playstation: return "playstation.logo"
        case .xbox: return "xbox.logo"
        case .nintendo: return "gamecontroller"
        case .mobile: return "iphone"
        }
    }
}

/// Подробности об игре с экрана деталей: описание, жанры, разработчики, скриншоты.
struct GameDetails {
    let about: String
    let genres: String
    let developers: String
    let screenshots: [URL]
    /// Средний рейтинг IGDB, приведённый к пятибалльной шкале.
    let rating: Double
    let ratingsCount: Int
    /// Ссылка на трейлер в YouTube.
    let trailerURL: URL?
    /// Магазины и официальный сайт.
    let links: [GameLink]
    let similarGames: [GamesStorage]
}

/// Внешняя ссылка с экрана игры: магазин или официальный сайт.
struct GameLink {
    let title: String
    let url: URL
}

/// Семейства платформ для фильтра списка.
enum PlatformFamily: CaseIterable {
    case pc
    case playstation
    case xbox
    case nintendo

    var title: String {
        switch self {
        case .pc: return "PC"
        case .playstation: return "PlayStation"
        case .xbox: return "Xbox"
        case .nintendo: return "Nintendo"
        }
    }

    /// Условие для where-фильтра IGDB. PC — конкретная платформа (id 6),
    /// консоли — семейства платформ (platform_family).
    fileprivate var igdbCondition: String {
        switch self {
        case .pc: return "platforms = (6)"
        case .playstation: return "platforms.platform_family = 1"
        case .xbox: return "platforms.platform_family = 2"
        case .nintendo: return "platforms.platform_family = 5"
        }
    }
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

// MARK: - Ответы IGDB

struct IGDBGame: Decodable {
    let id: Int
    let name: String
    let firstReleaseDate: TimeInterval?
    let cover: IGDBImage?
    let screenshots: [IGDBImage]?
    let platforms: [IGDBPlatform]?
}

struct IGDBPlatform: Decodable {
    let id: Int
    let name: String
    let platformFamily: Int?
}

struct IGDBGameDetail: Decodable {
    let summary: String?
    let genres: [IGDBNamed]?
    let involvedCompanies: [IGDBInvolvedCompany]?
    let screenshots: [IGDBImage]?
    let totalRating: Double?
    let totalRatingCount: Int?
    let videos: [IGDBVideo]?
    let websites: [IGDBWebsite]?
    let similarGames: [IGDBGame]?
}

struct IGDBVideo: Decodable {
    let videoId: String
}

struct IGDBWebsite: Decodable {
    let url: String
    let type: Int?
}

struct IGDBInvolvedCompany: Decodable {
    let company: IGDBNamed
    let developer: Bool
}

struct IGDBImage: Decodable {
    let imageId: String
}

struct IGDBNamed: Decodable {
    let name: String
}

struct TwitchToken: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
}

// MARK: - Сервис IGDB

final class IGDBService {

    /// Максимум записей на страницу (IGDB разрешает до 500).
    static let pageSize = 40

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Токен Twitch OAuth; живёт около двух месяцев и обновляется автоматически.
    private var accessToken: String?
    private var tokenExpiry = Date.distantPast

    func fetchGames(page: Int = 1, yearsAhead: Int = 3, search: String? = nil, platform: PlatformFamily? = nil, sortByHype: Bool = false) async throws -> (games: [GamesStorage], hasMore: Bool) {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .year, value: yearsAhead, to: now) ?? now

        // Основные игры, самостоятельные дополнения, ремейки, ремастеры,
        // расширенные издания и порты — но не DLC, эпизоды и сезоны.
        var conditions = [
            "first_release_date > \(Int(now.timeIntervalSince1970))",
            "first_release_date < \(Int(endDate.timeIntervalSince1970))",
            "game_type = (0,4,8,9,10,11)"
        ]
        if let platform {
            conditions.append(platform.igdbCondition)
        }
        if let search {
            // Поиск через `name ~ *"..."*`, а не `search`: search в IGDB
            // несовместим с sort, а список должен оставаться отсортированным по дате.
            let escaped = search
                .replacingOccurrences(of: "\\", with: "")
                .replacingOccurrences(of: "\"", with: "\\\"")
            conditions.append("name ~ *\"\(escaped)\"*")
        }
        if sortByHype {
            // hypes — сколько человек добавили игру в ожидаемое на IGDB.
            conditions.append("hypes != null")
        }

        let query = """
        fields name, first_release_date, cover.image_id, screenshots.image_id, platforms.name, platforms.platform_family;
        where \(conditions.joined(separator: " & "));
        sort \(sortByHype ? "hypes desc" : "first_release_date asc");
        limit \(Self.pageSize);
        offset \((page - 1) * Self.pageSize);
        """

        let data = try await requestData(endpoint: "games", query: query)
        let fetched = try decoder.decode([IGDBGame].self, from: data)

        return (fetched.map(gamesStorage(from:)), fetched.count == Self.pageSize)
    }

    /// Приводит игру IGDB к модели приложения.
    private func gamesStorage(from game: IGDBGame) -> GamesStorage {
        GamesStorage(
            id: game.id,
            gameTitle: game.name,
            // Скриншот горизонтальный и лучше смотрится в списке и на обложке
            // экрана деталей; портретная обложка — запасной вариант.
            imageURL: imageURL(game.screenshots?.first, size: "t_screenshot_big")
                ?? imageURL(game.cover, size: "t_cover_big"),
            releaseDate: game.firstReleaseDate.map { Date(timeIntervalSince1970: $0) },
            platforms: game.platforms?.map(\.name).joined(separator: ", ") ?? "",
            platformBadges: platformBadges(for: game.platforms)
        )
    }

    func fetchGameDetails(id: Int) async throws -> GameDetails {
        let query = """
        fields summary, genres.name, involved_companies.company.name, involved_companies.developer, screenshots.image_id, total_rating, total_rating_count, videos.video_id, websites.url, websites.type, similar_games.name, similar_games.first_release_date, similar_games.cover.image_id, similar_games.screenshots.image_id, similar_games.platforms.name, similar_games.platforms.platform_family;
        where id = \(id);
        """

        let data = try await requestData(endpoint: "games", query: query)
        guard let detail = try decoder.decode([IGDBGameDetail].self, from: data).first else {
            throw URLError(.resourceUnavailable)
        }

        return GameDetails(
            about: detail.summary ?? "",
            genres: detail.genres?.map(\.name).joined(separator: ", ") ?? "",
            developers: detail.involvedCompanies?
                .filter(\.developer)
                .map(\.company.name)
                .joined(separator: ", ") ?? "",
            screenshots: detail.screenshots?.compactMap { imageURL($0, size: "t_screenshot_huge") } ?? [],
            // IGDB считает рейтинг по 100-балльной шкале, приложение показывает пятибалльную.
            rating: (detail.totalRating ?? 0) / 20,
            ratingsCount: detail.totalRatingCount ?? 0,
            trailerURL: detail.videos?.first.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.videoId)") },
            links: links(from: detail.websites),
            similarGames: detail.similarGames?.map(gamesStorage(from:)) ?? []
        )
    }

    /// Отбирает магазины и официальный сайт из ссылок IGDB (websites.type).
    private func links(from websites: [IGDBWebsite]?) -> [GameLink] {
        let knownTypes: [(type: Int, title: String)] = [
            (13, "Steam"),
            (23, "PlayStation Store"),
            (22, "Xbox Store"),
            (24, "Nintendo eShop"),
            (16, "Epic Games"),
            (17, "GOG"),
            (1, String(localized: "Official Website"))
        ]

        return knownTypes.compactMap { known in
            guard let site = websites?.first(where: { $0.type == known.type }),
                  let url = URL(string: site.url) else { return nil }
            return GameLink(title: known.title, url: url)
        }
    }

    // MARK: - Запросы и авторизация

    private func requestData(endpoint: String, query: String) async throws -> Data {
        let token = try await validToken()

        var request = URLRequest(url: URL(string: "https://api.igdb.com/v4/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue(Secrets.igdbClientID, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = query.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func validToken() async throws -> String {
        if let accessToken, tokenExpiry > Date() {
            return accessToken
        }

        var components = URLComponents(string: "https://id.twitch.tv/oauth2/token")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Secrets.igdbClientID),
            URLQueryItem(name: "client_secret", value: Secrets.igdbClientSecret),
            URLQueryItem(name: "grant_type", value: "client_credentials")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try decoder.decode(TwitchToken.self, from: data)

        accessToken = token.accessToken
        // Обновляем токен на минуту раньше срока, чтобы не поймать 401 на границе.
        tokenExpiry = Date().addingTimeInterval(token.expiresIn - 60)
        return token.accessToken
    }

    /// Сводит конкретные платформы IGDB к иконкам: консоли — по семейству
    /// (1 PlayStation, 2 Xbox, 5 Nintendo, 4 Linux), остальные — по id платформы.
    private func platformBadges(for platforms: [IGDBPlatform]?) -> [PlatformBadge] {
        var badges = Set<PlatformBadge>()

        for platform in platforms ?? [] {
            switch platform.platformFamily {
            case 1: badges.insert(.playstation)
            case 2: badges.insert(.xbox)
            case 5: badges.insert(.nintendo)
            case 4: badges.insert(.pc)
            default:
                switch platform.id {
                case 6, 14, 3: badges.insert(.pc)      // Windows, Mac, Linux
                case 34, 39: badges.insert(.mobile)    // Android, iOS
                default: break
                }
            }
        }

        return PlatformBadge.allCases.filter(badges.contains)
    }

    private func imageURL(_ image: IGDBImage?, size: String) -> URL? {
        guard let image else { return nil }
        return URL(string: "https://images.igdb.com/igdb/image/upload/\(size)/\(image.imageId).jpg")
    }

}
