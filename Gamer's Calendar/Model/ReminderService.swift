
import Foundation
import UserNotifications

/// Отслеживаемые игры: локальное уведомление утром в день релиза
/// плюс сохранённый снимок игры для вкладки «Жду».
final class ReminderService {

    static let shared = ReminderService()

    private let defaults = UserDefaults.standard
    private let storageKey = "trackedGames"

    private init() {}

    /// Игры с включённым напоминанием, отсортированные по дате релиза.
    private(set) var trackedGames: [GamesStorage] {
        get {
            guard let data = defaults.data(forKey: storageKey),
                  let games = try? JSONDecoder().decode([GamesStorage].self, from: data) else {
                return []
            }
            return games
        }
        set {
            let sorted = newValue.sorted {
                ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture)
            }
            defaults.set(try? JSONEncoder().encode(sorted), forKey: storageKey)
        }
    }

    func hasReminder(for gameID: Int) -> Bool {
        trackedGames.contains { $0.id == gameID }
    }

    /// Включает напоминание. Возвращает false, если пользователь
    /// не дал разрешение на уведомления.
    func addReminder(for game: GamesStorage) async -> Bool {
        guard let releaseDate = game.releaseDate else { return false }

        let center = UNUserNotificationCenter.current()
        let authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard authorized else { return false }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: releaseDate)
        components.hour = 10

        let content = UNMutableNotificationContent()
        content.title = game.gameTitle
        content.body = String(localized: "Releases today!")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: notificationID(for: game.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)

        trackedGames = trackedGames.filter { $0.id != game.id } + [game]
        return true
    }

    func removeReminder(for gameID: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID(for: gameID)])
        trackedGames = trackedGames.filter { $0.id != gameID }
    }

    private func notificationID(for gameID: Int) -> String {
        "game-release-\(gameID)"
    }

}
