
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
    /// Сколько человек ждут игру на IGDB — для выбора постера дня в сетке.
    let hypes: Int?
    /// Постеры по приоритету: арт → обложка → скриншот. Первый может
    /// оказаться пустым файлом, тогда загрузчик берёт следующий.
    /// Optional — для декодирования данных, сохранённых старыми версиями.
    let imageCandidates: [URL]?
    /// Вертикальная обложка — для клеток календарной сетки.
    let coverURL: URL?
    /// Все ключевые арты игры: загрузчик выбирает из них самый детализированный.
    let artworkURLs: [URL]?

    /// Кандидаты постера с фолбэком для старых сохранённых данных.
    var posterCandidates: [URL] {
        if let imageCandidates, !imageCandidates.isEmpty {
            return imageCandidates
        }
        return [imageURL].compactMap { $0 }
    }

    /// Кандидаты вертикального превью: обложка приоритетнее арта.
    var portraitPosterCandidates: [URL] {
        guard let coverURL else { return posterCandidates }
        return [coverURL] + posterCandidates.filter { $0 != coverURL }
    }
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
    /// Первая франшиза игры, если есть.
    let franchise: GameFranchise?
    /// Страница игры на igdb.com — для шаринга.
    let pageURL: URL?
}

/// Франшиза для перехода к списку всех игр серии.
struct GameFranchise {
    let id: Int
    let name: String
}

/// Внешняя ссылка с экрана игры: магазин или официальный сайт.
struct GameLink {
    let title: String
    let url: URL
}

/// Жанры IGDB для фильтра списка (raw value — id из справочника genres,
/// он же ключ в UserDefaults).
enum GenreFilter: Int, CaseIterable {
    case rpg = 12
    case shooter = 5
    case adventure = 31
    case strategy = 15
    case indie = 32
    case simulator = 13
    case racing = 10
    case platformer = 8

    var title: String {
        switch self {
        case .rpg: return String(localized: "RPG")
        case .shooter: return String(localized: "Shooter")
        case .adventure: return String(localized: "Adventure")
        case .strategy: return String(localized: "Strategy")
        case .indie: return String(localized: "Indie")
        case .simulator: return String(localized: "Simulator")
        case .racing: return String(localized: "Racing")
        case .platformer: return String(localized: "Platformer")
        }
    }
}

/// Семейства платформ для фильтра списка. Raw value хранится в UserDefaults.
enum PlatformFamily: String, CaseIterable {
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

    /// Горизонтальный постер игры. Среди артов выбирается самый большой
    /// по весу файл (HEAD-запросы): детализированный постер с логотипом
    /// весит в разы больше пустышек и тёмных заглушек. Фолбэки — скриншот
    /// и обложка через обычную цепочку кандидатов.
    func loadPoster(for game: GamesStorage) async -> UIImage? {
        let artworks = game.artworkURLs ?? []

        // Выбранный ранее арт уже в памяти — берём его.
        for url in artworks {
            if let cached = image(for: url) {
                return cached
            }
        }

        if let best = await richestURL(among: artworks),
           let image = await loadImage(fromCandidates: [best]) {
            return image
        }

        return await loadImage(fromCandidates: game.posterCandidates)
    }

    /// URL самого детализированного арта. CDN IGDB не отдаёт размер файла
    /// в заголовках, поэтому скачиваем миниатюры (t_thumb, пара КБ каждая)
    /// и сравниваем их «содержательность»: вес файла со штрафом за белый фон.
    /// Пустышки весят копейки, а карточки-логотипы на белом фоне проигрывают
    /// настоящим постерам, даже если их миниатюра чуть тяжелее.
    private func richestURL(among urls: [URL]) async -> URL? {
        guard !urls.isEmpty else { return nil }

        return await withTaskGroup(of: (url: URL, score: Int)?.self) { group in
            for url in urls {
                group.addTask { [session] in
                    let thumbPath = url.absoluteString.replacingOccurrences(of: "/t_720p/", with: "/t_thumb/")
                    guard let thumbURL = URL(string: thumbPath),
                          let (data, _) = try? await session.data(from: thumbURL),
                          data.count > 1000 else { return nil }

                    return (url, Self.contentScore(ofThumb: data))
                }
            }

            var best: (url: URL, score: Int)?
            for await candidate in group {
                if let candidate, candidate.score > (best?.score ?? 0) {
                    best = candidate
                }
            }
            return best?.url
        }
    }

    /// Оценка «содержательности» миниатюры: вес файла, умноженный на долю
    /// небелых пикселей. Карточка-логотип на белом фоне получает низкий балл.
    private static func contentScore(ofThumb data: Data) -> Int {
        guard let cgImage = UIImage(data: data)?.cgImage else { return 0 }

        let width = 24
        let height = 14
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return data.count }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var whiteCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[index] > 245, pixels[index + 1] > 245, pixels[index + 2] > 245 {
                whiteCount += 1
            }
        }

        let whiteFraction = Double(whiteCount) / Double(width * height)
        return Int(Double(data.count) * (1.0 - whiteFraction))
    }

    /// Первая «содержательная» картинка из кандидатов. У IGDB встречаются
    /// пустые белые артворки — такие JPEG весят считаные килобайты,
    /// отсекаем их по размеру файла и берём следующий вариант.
    /// Приоритет строгий: закэшированный менее приоритетный кандидат не должен
    /// обгонять более приоритетный (сетке нужна именно вертикальная обложка).
    func loadImage(fromCandidates urls: [URL]) async -> UIImage? {
        for url in urls {
            if let cached = image(for: url) {
                return cached
            }

            guard let (data, _) = try? await session.data(from: url),
                  data.count > 6000,
                  let image = UIImage(data: data) else { continue }

            cache.setObject(image, forKey: url as NSURL)
            return image
        }

        return nil
    }
}

/// Дисковый кэш первой страницы списка: при запуске игры показываются
/// мгновенно, пока по сети грузится свежая версия.
enum FirstPageCache {

    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("firstPage.json")
    }

    static func load() -> [GamesStorage] {
        guard let data = try? Data(contentsOf: fileURL),
              let games = try? JSONDecoder().decode([GamesStorage].self, from: data) else {
            return []
        }
        return games
    }

    static func save(_ games: [GamesStorage]) {
        try? JSONEncoder().encode(games).write(to: fileURL)
    }

}

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
        fields summary, url, genres.name, involved_companies.company.name, involved_companies.developer, screenshots.image_id, total_rating, total_rating_count, videos.video_id, websites.url, websites.type, franchises.name, similar_games.name, similar_games.first_release_date, similar_games.cover.image_id, similar_games.artworks.image_id, similar_games.screenshots.image_id, similar_games.platforms.name, similar_games.platforms.platform_family;
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
            similarGames: detail.similarGames?.map(gamesStorage(from:)) ?? [],
            franchise: detail.franchises?.first.map { GameFranchise(id: $0.id, name: $0.name) },
            pageURL: detail.url.flatMap(URL.init(string:))
        )
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

}
