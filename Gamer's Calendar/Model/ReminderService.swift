
import Foundation
import UserNotifications

/// Напоминания о выходе игр: локальное уведомление утром в день релиза.
/// Список игр с включённым напоминанием хранится в UserDefaults.
final class ReminderService {

    static let shared = ReminderService()

    private let defaults = UserDefaults.standard
    private let storageKey = "remindedGameIDs"

    private init() {}

    private var remindedIDs: Set<Int> {
        get { Set(defaults.array(forKey: storageKey) as? [Int] ?? []) }
        set { defaults.set(Array(newValue), forKey: storageKey) }
    }

    func hasReminder(for gameID: Int) -> Bool {
        remindedIDs.contains(gameID)
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

        remindedIDs.insert(game.id)
        return true
    }

    func removeReminder(for gameID: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID(for: gameID)])
        remindedIDs.remove(gameID)
    }

    private func notificationID(for gameID: Int) -> String {
        "game-release-\(gameID)"
    }

}
