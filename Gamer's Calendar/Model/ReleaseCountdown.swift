
import Foundation
import ActivityKit

/// Атрибуты Live Activity с отсчётом до релиза. Идентичная копия объявлена
/// в таргете виджета — система сопоставляет активности по имени типа.
@available(iOS 16.1, *)
struct ReleaseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    let gameTitle: String
    let releaseDate: Date
    let compactCountdown: String
}

/// Запуск отсчёта до релиза на экране блокировки и в Dynamic Island.
@available(iOS 16.2, *)
enum ReleaseCountdown {

    /// Возвращает false, если Live Activities выключены или релиз уже случился.
    static func start(for game: GamesStorage) -> Bool {
        guard let releaseDate = game.releaseDate, releaseDate > .now,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            return false
        }

        let attributes = ReleaseActivityAttributes(
            gameTitle: game.gameTitle,
            releaseDate: releaseDate,
            compactCountdown: compactCountdownText(until: releaseDate)
        )
        do {
            _ = try Activity.request(attributes: attributes, content: .init(state: .init(), staleDate: nil))
            return true
        } catch {
            return false
        }
    }

    private static func compactCountdownText(until releaseDate: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.startOfDay(for: releaseDate)
        let components = calendar.dateComponents([.year, .month, .day], from: start, to: end)

        if let years = components.year, years > 0 {
            return "\(years)y"
        }
        if let months = components.month, months > 0 {
            return "\(months)mo"
        }

        return "\(max(components.day ?? 0, 1))d"
    }

}
