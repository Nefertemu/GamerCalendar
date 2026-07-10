
import Foundation

/// Источник данных об играх. Боевая реализация — IGDBService,
/// в тестах подставляется мок.
protocol GameCatalogService {

    /// Страница предстоящих релизов с фильтрами и сортировкой.
    func fetchGames(page: Int, monthsAhead: Int, search: String?, platform: PlatformFamily?, genre: GenreFilter?, sortByHype: Bool) async throws -> (games: [GamesStorage], hasMore: Bool)

    /// Конкретные игры по id — для сверки дат отслеживаемых игр.
    func fetchGames(ids: [Int]) async throws -> [GamesStorage]

    /// Все релизы в интервале дат — для календарной сетки.
    func fetchGames(from startDate: Date, to endDate: Date) async throws -> [GamesStorage]

    /// Все игры франшизы, новые сверху.
    func fetchFranchiseGames(franchiseID: Int) async throws -> [GamesStorage]

    /// Подробности для экрана игры.
    func fetchGameDetails(id: Int) async throws -> GameDetails

}
