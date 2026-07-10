import Foundation

/// Offline-first wrapper around the IGDB catalog. Fresh network responses are
/// saved to disk; if the network fails later, screens keep showing recent data.
final class CachedGameCatalogService: GameCatalogService {

    private let base: GameCatalogService
    private let cache = CatalogDiskCache()

    init(base: GameCatalogService = IGDBService()) {
        self.base = base
    }

    func fetchGames(page: Int, monthsAhead: Int, search: String?, platform: PlatformFamily?, genre: GenreFilter?, sortByHype: Bool) async throws -> (games: [GamesStorage], hasMore: Bool) {
        let key = "feed-\(page)-\(monthsAhead)-\(search ?? "_")-\(platform?.rawValue ?? "_")-\(genre?.rawValue ?? -1)-\(sortByHype)"

        do {
            let result = try await base.fetchGames(
                page: page,
                monthsAhead: monthsAhead,
                search: search,
                platform: platform,
                genre: genre,
                sortByHype: sortByHype
            )
            cache.save(result, for: key)
            return result
        } catch {
            if let cached: PagedGamesCache = cache.load(key) {
                return (cached.games, cached.hasMore)
            }
            throw error
        }
    }

    func fetchGames(ids: [Int]) async throws -> [GamesStorage] {
        let key = "ids-\(ids.sorted().map(String.init).joined(separator: "-"))"

        do {
            let games = try await base.fetchGames(ids: ids)
            cache.save(games, for: key)
            return games
        } catch {
            if let cached: [GamesStorage] = cache.load(key) {
                return cached
            }
            throw error
        }
    }

    func fetchGames(from startDate: Date, to endDate: Date) async throws -> [GamesStorage] {
        let start = Calendar.current.startOfDay(for: startDate).timeIntervalSince1970
        let end = Calendar.current.startOfDay(for: endDate).timeIntervalSince1970
        let key = "month-\(Int(start))-\(Int(end))"

        do {
            let games = try await base.fetchGames(from: startDate, to: endDate)
            cache.save(games, for: key)
            return games
        } catch {
            if let cached: [GamesStorage] = cache.load(key) {
                return cached
            }
            throw error
        }
    }

    func fetchFranchiseGames(franchiseID: Int) async throws -> [GamesStorage] {
        let key = "franchise-\(franchiseID)"

        do {
            let games = try await base.fetchFranchiseGames(franchiseID: franchiseID)
            cache.save(games, for: key)
            return games
        } catch {
            if let cached: [GamesStorage] = cache.load(key) {
                return cached
            }
            throw error
        }
    }

    func fetchGameDetails(id: Int) async throws -> GameDetails {
        let key = "details-\(id)"

        do {
            let details = try await base.fetchGameDetails(id: id)
            cache.save(details, for: key)
            return details
        } catch {
            if let cached: GameDetails = cache.load(key) {
                return cached
            }
            throw error
        }
    }

}

private struct PagedGamesCache: Codable {
    let games: [GamesStorage]
    let hasMore: Bool
}

enum CatalogCacheMaintenance {

    static func clear() {
        let directoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CatalogCache", isDirectory: true)
        try? FileManager.default.removeItem(at: directoryURL)
    }

}

private final class CatalogDiskCache {

    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        directoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CatalogCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, for key: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: url(for: key), options: .atomic)
    }

    private func url(for key: String) -> URL {
        directoryURL.appendingPathComponent(safeFileName(from: key)).appendingPathExtension("json")
    }

    private func safeFileName(from key: String) -> String {
        key.map { character in
            character.isLetter || character.isNumber || character == "-" ? character : "_"
        }.map(String.init).joined()
    }

}

private extension CatalogDiskCache {

    func save(_ value: (games: [GamesStorage], hasMore: Bool), for key: String) {
        save(PagedGamesCache(games: value.games, hasMore: value.hasMore), for: key)
    }

}
