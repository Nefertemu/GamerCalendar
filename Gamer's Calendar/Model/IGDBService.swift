import Foundation

// MARK: - Ответы IGDB

struct IGDBGame: Decodable {
    let id: Int
    let name: String
    let firstReleaseDate: TimeInterval?
    let cover: IGDBImage?
    let artworks: [IGDBImage]?
    let screenshots: [IGDBImage]?
    let platforms: [IGDBPlatform]?
    let hypes: Int?
    /// Основная игра для изданий (Ultimate Edition и т.п.) —
    /// у самих изданий часто нет ни артов, ни скриншотов.
    let versionParent: IGDBParentGame?
}

struct IGDBParentGame: Decodable {
    let artworks: [IGDBImage]?
    let screenshots: [IGDBImage]?
}

struct IGDBPlatform: Decodable {
    let id: Int
    let name: String
    let platformFamily: Int?
}

struct IGDBGameDetail: Decodable {
    let summary: String?
    let url: String?
    let genres: [IGDBNamed]?
    let involvedCompanies: [IGDBInvolvedCompany]?
    let screenshots: [IGDBImage]?
    let firstReleaseDate: TimeInterval?
    let releaseDates: [IGDBReleaseDate]?
    let totalRating: Double?
    let totalRatingCount: Int?
    let videos: [IGDBVideo]?
    let websites: [IGDBWebsite]?
    let similarGames: [IGDBGame]?
    let franchises: [IGDBFranchise]?
}

struct IGDBFranchise: Decodable {
    let id: Int
    let name: String
}

struct IGDBVideo: Decodable {
    let videoId: String
}

struct IGDBWebsite: Decodable {
    let url: String
    let type: Int?
}

struct IGDBReleaseDate: Decodable {
    let category: Int?
    let date: TimeInterval?
    let human: String?
    let m: Int?
    let y: Int?
    let d: Int?
    let platform: IGDBPlatform?
    let status: IGDBNamed?
    let dateFormat: IGDBDateFormat?
    let releaseRegion: IGDBReleaseRegion?
    let region: Int?
}

struct IGDBDateFormat: Decodable {
    let format: String?
}

struct IGDBReleaseRegion: Decodable {
    let region: String?
}

struct IGDBInvolvedCompany: Decodable {
    let company: IGDBNamed
    let developer: Bool
}

struct IGDBImage: Decodable {
    let imageId: String
    let width: Int?
    let height: Int?
}

struct IGDBNamed: Decodable {
    let name: String
}

struct TwitchToken: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
}

// MARK: - Сервис IGDB

enum IGDBServiceError: LocalizedError {
    case invalidResponse
    case missingCredentials
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Unexpected IGDB response")
        case .missingCredentials:
            return String(localized: "Missing IGDB credentials")
        case let .requestFailed(statusCode, body):
            guard !body.isEmpty else {
                return String(localized: "IGDB request failed with status \(statusCode)")
            }
            return String(localized: "IGDB request failed with status \(statusCode): \(body)")
        }
    }
}

private extension PlatformFamily {

    /// Условие для where-фильтра IGDB. PC — конкретная платформа (id 6),
    /// консоли — семейства платформ (platform_family).
    var igdbCondition: String {
        switch self {
        case .pc: return "platforms = (6)"
        case .playstation: return "platforms.platform_family = 1"
        case .xbox: return "platforms.platform_family = 2"
        case .nintendo: return "platforms.platform_family = 5"
        }
    }

}

final class IGDBService: GameCatalogService {

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

    func fetchGames(page: Int = 1, monthsAhead: Int = 36, search: String? = nil, platform: PlatformFamily? = nil, genre: GenreFilter? = nil, sortByHype: Bool = false) async throws -> (games: [GamesStorage], hasMore: Bool) {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .month, value: monthsAhead, to: now) ?? now

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
        if let genre {
            conditions.append("genres = (\(genre.rawValue))")
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
        fields \(Self.listFields);
        where \(conditions.joined(separator: " & "));
        sort \(sortByHype ? "hypes desc" : "first_release_date asc");
        limit \(Self.pageSize);
        offset \((page - 1) * Self.pageSize);
        """

        let data = try await requestData(endpoint: "games", query: query)
        let fetched = try decoder.decode([IGDBGame].self, from: data)

        return (fetched.map(gamesStorage(from:)), fetched.count == Self.pageSize)
    }

    /// Поля списочного запроса: всё, что нужно для GamesStorage.
    private static let listFields = "name, first_release_date, cover.image_id, artworks.image_id, artworks.width, artworks.height, screenshots.image_id, platforms.name, platforms.platform_family, hypes, version_parent.artworks.image_id, version_parent.artworks.width, version_parent.artworks.height, version_parent.screenshots.image_id"

    /// Загружает конкретные игры по их id — для сверки дат отслеживаемых игр.
    func fetchGames(ids: [Int]) async throws -> [GamesStorage] {
        guard !ids.isEmpty else { return [] }

        let query = """
        fields \(Self.listFields);
        where id = (\(ids.map(String.init).joined(separator: ",")));
        limit \(ids.count);
        """

        let data = try await requestData(endpoint: "games", query: query)
        return try decoder.decode([IGDBGame].self, from: data).map(gamesStorage(from:))
    }

    /// Релизы в интервале дат одним запросом — для календарной сетки.
    /// В месяце бывает больше 500 игр (лимит IGDB), поэтому сортируем
    /// по хайпу: заметные релизы попадают в сетку гарантированно,
    /// и первой игрой дня (постером клетки) становится самая ожидаемая.
    func fetchGames(from startDate: Date, to endDate: Date) async throws -> [GamesStorage] {
        let query = """
        fields \(Self.listFields);
        where first_release_date >= \(Int(startDate.timeIntervalSince1970)) & first_release_date < \(Int(endDate.timeIntervalSince1970)) & game_type = (0,4,8,9,10,11);
        sort hypes desc;
        limit 500;
        """

        let data = try await requestData(endpoint: "games", query: query)
        return try decoder.decode([IGDBGame].self, from: data).map(gamesStorage(from:))
    }

    /// Все игры франшизы, новые сверху.
    func fetchFranchiseGames(franchiseID: Int) async throws -> [GamesStorage] {
        let query = """
        fields \(Self.listFields);
        where franchises = (\(franchiseID)) & game_type = (0,4,8,9,10,11);
        sort first_release_date desc;
        limit 500;
        """

        let data = try await requestData(endpoint: "games", query: query)
        return try decoder.decode([IGDBGame].self, from: data).map(gamesStorage(from:))
    }

    /// Приводит игру IGDB к модели приложения. Internal для юнит-тестов.
    func gamesStorage(from game: IGDBGame) -> GamesStorage {
        // Горизонтальные превью: ключевые арты (берём несколько — первый
        // бывает пустым файлом), затем скриншот. У изданий своих картинок
        // часто нет — наследуем от основной игры (version_parent). Портретная
        // обложка — самый последний вариант: в горизонтальном слоте она режется.
        // Размер t_720p вписывает картинку без обрезки; размеры вида
        // t_screenshot_big кропят до фиксированных пропорций прямо на CDN.
        let ownArtworks = game.artworks ?? []
        let artworks = ownArtworks.isEmpty ? (game.versionParent?.artworks ?? []) : ownArtworks

        // Только альбомные арты: издатели заливают в artworks и портретные
        // бокс-арты — им в горизонтальном слоте не место, для этого есть
        // скриншоты и обложка. Арты без размеров считаем альбомными.
        let landscapeArtworks = artworks.filter { ($0.width ?? 2) > ($0.height ?? 1) }
        let artworkURLs = landscapeArtworks.prefix(5).compactMap { imageURL($0, size: "t_720p") }

        let screenshot = game.screenshots?.first ?? game.versionParent?.screenshots?.first
        let candidates = artworkURLs + [
            imageURL(screenshot, size: "t_720p"),
            imageURL(game.cover, size: "t_cover_big")
        ].compactMap { $0 }

        return GamesStorage(
            id: game.id,
            gameTitle: game.name,
            imageURL: candidates.first,
            releaseDate: game.firstReleaseDate.map { Date(timeIntervalSince1970: $0) },
            platforms: game.platforms?.map(\.name).joined(separator: ", ") ?? "",
            platformBadges: platformBadges(for: game.platforms),
            hypes: game.hypes,
            imageCandidates: candidates,
            coverURL: imageURL(game.cover, size: "t_cover_big"),
            artworkURLs: artworkURLs
        )
    }

    func fetchGameDetails(id: Int) async throws -> GameDetails {
        let query = """
        fields summary, url, first_release_date, genres.name, involved_companies.company.name, involved_companies.developer, screenshots.image_id, release_dates.date, release_dates.human, release_dates.y, release_dates.m, release_dates.d, release_dates.category, release_dates.platform.name, release_dates.platform.platform_family, release_dates.status.name, release_dates.date_format.format, release_dates.release_region.region, release_dates.region, total_rating, total_rating_count, videos.video_id, websites.url, websites.type, franchises.name, similar_games.name, similar_games.first_release_date, similar_games.cover.image_id, similar_games.artworks.image_id, similar_games.screenshots.image_id, similar_games.platforms.name, similar_games.platforms.platform_family;
        where id = \(id);
        """

        let data = try await requestData(endpoint: "games", query: query)
        guard let detail = try decoder.decode([IGDBGameDetail].self, from: data).first else {
            throw URLError(.resourceUnavailable)
        }

        let links = links(from: detail.websites)
        let releaseDates = platformReleaseDates(from: detail.releaseDates)

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
            links: links,
            similarGames: detail.similarGames?.map(gamesStorage(from:)) ?? [],
            releaseDates: releaseDates,
            releaseAccuracy: releaseAccuracy(from: detail.releaseDates, fallbackDate: detail.firstReleaseDate),
            preorderAvailable: hasPreorderAvailable(links: links, firstReleaseDate: detail.firstReleaseDate),
            updateBadges: updateBadges(for: detail, releaseDates: releaseDates, links: links),
            franchise: detail.franchises?.first.map { GameFranchise(id: $0.id, name: $0.name) },
            pageURL: detail.url.flatMap(URL.init(string:))
        )
    }

    /// Даты по платформам/регионам с сохранением точности даты из IGDB.
    private func platformReleaseDates(from releaseDates: [IGDBReleaseDate]?) -> [PlatformReleaseDate] {
        var seen = Set<String>()

        return (releaseDates ?? [])
            .sorted { lhs, rhs in
                (lhs.date ?? .greatestFiniteMagnitude) < (rhs.date ?? .greatestFiniteMagnitude)
            }
            .compactMap { releaseDate in
                let platform = releaseDate.platform?.name ?? String(localized: "Unknown platform")
                let region = releaseRegionName(from: releaseDate)
                let accuracy = releaseAccuracy(from: releaseDate)
                let displayDate = displayDate(for: releaseDate, accuracy: accuracy)
                let key = "\(platform)|\(region)|\(displayDate)"

                guard seen.insert(key).inserted else { return nil }

                return PlatformReleaseDate(
                    platformName: platform,
                    regionName: region,
                    displayDate: displayDate,
                    accuracy: accuracy,
                    status: releaseDate.status?.name,
                    timestamp: releaseDate.date.map { Date(timeIntervalSince1970: $0) }
                )
            }
    }

    private func releaseAccuracy(from releaseDates: [IGDBReleaseDate]?, fallbackDate: TimeInterval?) -> ReleaseAccuracy {
        let accuracies = (releaseDates ?? []).map(releaseAccuracy(from:))
        if accuracies.contains(.exact) { return .exact }
        if accuracies.contains(.month) { return .month }
        if accuracies.contains(.quarter) { return .quarter }
        if accuracies.contains(.year) { return .year }
        if accuracies.contains(.tba) { return .tba }
        return fallbackDate == nil ? .unknown : .exact
    }

    private func releaseAccuracy(from releaseDate: IGDBReleaseDate) -> ReleaseAccuracy {
        let format = releaseDate.dateFormat?.format?.lowercased() ?? ""
        let human = releaseDate.human?.lowercased() ?? ""

        if format.contains("tbd") || format.contains("tba") { return .tba }
        if format.contains("quarter") || format.contains("q") { return .quarter }
        if format.contains("yyyy") && format.contains("mmmm") && format.contains("dd") { return .exact }
        if format.contains("dd") { return .exact }
        if format.contains("yyyy") && format.contains("mmmm") { return .month }
        if format == "yyyy" { return .year }

        switch releaseDate.category {
        case 0: return .exact
        case 1: return .month
        case 2: return .year
        case 3, 4, 5, 6: return .quarter
        case 7: return .tba
        default:
            if releaseDate.d != nil || releaseDate.date != nil || human.range(of: #"\d{1,2}"#, options: .regularExpression) != nil {
                return .exact
            }
            if releaseDate.m != nil { return .month }
            if releaseDate.y != nil { return .year }
            return .unknown
        }
    }

    private func displayDate(for releaseDate: IGDBReleaseDate, accuracy: ReleaseAccuracy) -> String {
        if accuracy == .tba {
            return "TBA"
        }
        if let human = releaseDate.human, !human.isEmpty {
            return human
        }
        if let date = releaseDate.date {
            return Date(timeIntervalSince1970: date).formatted(date: .abbreviated, time: .omitted)
        }
        if let year = releaseDate.y {
            if accuracy == .quarter, let quarter = quarterName(for: releaseDate.category) {
                return "\(quarter) \(year)"
            }
            if let month = releaseDate.m {
                let symbols = DateFormatter().monthSymbols ?? []
                if symbols.indices.contains(month - 1) {
                    return "\(symbols[month - 1]) \(year)"
                }
            }
            return String(year)
        }
        return String(localized: "Unknown date")
    }

    private func quarterName(for category: Int?) -> String? {
        switch category {
        case 3: return "Q1"
        case 4: return "Q2"
        case 5: return "Q3"
        case 6: return "Q4"
        default: return nil
        }
    }

    private func releaseRegionName(from releaseDate: IGDBReleaseDate) -> String {
        if let region = releaseDate.releaseRegion?.region, !region.isEmpty {
            return region
        }

        switch releaseDate.region {
        case 1: return "Europe"
        case 2: return "North America"
        case 3: return "Australia"
        case 4: return "New Zealand"
        case 5: return "Japan"
        case 6: return "China"
        case 7: return "Asia"
        case 8: return String(localized: "Worldwide")
        case 9: return "Korea"
        case 10: return "Brazil"
        default: return String(localized: "Worldwide")
        }
    }

    private func hasPreorderAvailable(links: [GameLink], firstReleaseDate: TimeInterval?) -> Bool {
        guard let firstReleaseDate, Date(timeIntervalSince1970: firstReleaseDate) > .now else {
            return false
        }
        return links.contains { link in
            link.title != String(localized: "Official Website")
        }
    }

    private func updateBadges(for detail: IGDBGameDetail, releaseDates: [PlatformReleaseDate], links: [GameLink]) -> [GameUpdateBadge] {
        var badges: [GameUpdateBadge] = []

        let accuracy = releaseAccuracy(from: detail.releaseDates, fallbackDate: detail.firstReleaseDate)
        if accuracy != .exact {
            badges.append(GameUpdateBadge(
                title: String(localized: "Release date is not final"),
                detail: accuracy.title
            ))
        }

        if hasPreorderAvailable(links: links, firstReleaseDate: detail.firstReleaseDate) {
            badges.append(GameUpdateBadge(
                title: String(localized: "Preorder available"),
                detail: links.filter { $0.title != String(localized: "Official Website") }.map(\.title).joined(separator: ", ")
            ))
        }

        let distinctPlatforms = Set(releaseDates.map(\.platformName))
        if distinctPlatforms.count > 1 {
            badges.append(GameUpdateBadge(
                title: String(localized: "Platform dates available"),
                detail: String(localized: "\(distinctPlatforms.count) platforms")
            ))
        }

        return badges
    }

    /// Отбирает магазины и официальный сайт из ссылок IGDB (websites.type).
    /// Internal для юнит-тестов.
    func links(from websites: [IGDBWebsite]?) -> [GameLink] {
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

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validToken() async throws -> String {
        if let accessToken, tokenExpiry > Date() {
            return accessToken
        }

        guard !Secrets.igdbClientID.isEmpty, !Secrets.igdbClientSecret.isEmpty else {
            throw IGDBServiceError.missingCredentials
        }

        var components = URLComponents(string: "https://id.twitch.tv/oauth2/token")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Secrets.igdbClientID),
            URLQueryItem(name: "client_secret", value: Secrets.igdbClientSecret),
            URLQueryItem(name: "grant_type", value: "client_credentials")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let token = try decoder.decode(TwitchToken.self, from: data)

        accessToken = token.accessToken
        // Обновляем токен на минуту раньше срока, чтобы не поймать 401 на границе.
        tokenExpiry = Date().addingTimeInterval(token.expiresIn - 60)
        return token.accessToken
    }

    /// Сводит конкретные платформы IGDB к иконкам: консоли — по семейству
    /// (1 PlayStation, 2 Xbox, 5 Nintendo, 4 Linux), остальные — по id платформы.
    /// Internal для юнит-тестов.
    func platformBadges(for platforms: [IGDBPlatform]?) -> [PlatformBadge] {
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

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IGDBServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw IGDBServiceError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
    }

}
