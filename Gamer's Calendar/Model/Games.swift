import Foundation

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

    /// Альбомные кандидаты для широких превью в списках.
    var landscapePosterCandidates: [URL] {
        var seen = Set<URL>()
        let candidates = (artworkURLs ?? []) + posterCandidates.filter { $0 != coverURL }
        return candidates.filter { seen.insert($0).inserted }
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
struct GameDetails: Codable {
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
    let releaseDates: [PlatformReleaseDate]
    let releaseAccuracy: ReleaseAccuracy
    let preorderAvailable: Bool
    let updateBadges: [GameUpdateBadge]
    /// Первая франшиза игры, если есть.
    let franchise: GameFranchise?
    /// Страница игры на igdb.com — для шаринга.
    let pageURL: URL?
}

/// Франшиза для перехода к списку всех игр серии.
struct GameFranchise: Codable {
    let id: Int
    let name: String
}

/// Внешняя ссылка с экрана игры: магазин или официальный сайт.
struct GameLink: Codable {
    let title: String
    let url: URL
}

/// Дата релиза с точностью, которую реально отдал IGDB.
struct PlatformReleaseDate: Codable {
    let platformName: String
    let regionName: String
    let displayDate: String
    let accuracy: ReleaseAccuracy
    let status: String?
    let timestamp: Date?
}

enum ReleaseAccuracy: String, Codable {
    case exact
    case month
    case year
    case quarter
    case tba
    case unknown

    var title: String {
        switch self {
        case .exact:
            return String(localized: "Exact date")
        case .month:
            return String(localized: "Month announced")
        case .year:
            return String(localized: "Year announced")
        case .quarter:
            return String(localized: "Quarter announced")
        case .tba:
            return "TBA"
        case .unknown:
            return String(localized: "Unknown date")
        }
    }
}

struct GameUpdateBadge: Codable {
    let title: String
    let detail: String
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
