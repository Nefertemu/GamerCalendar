
import Foundation
import UserNotifications
import WidgetKit

/// Отслеживаемые игры: локальное уведомление утром в день релиза
/// плюс сохранённый снимок игры для вкладки «Жду» и виджета.
final class ReminderService {

    static let shared = ReminderService()

    /// Общий контейнер с виджетом. Если App Group недоступна
    /// (например, не настроена подпись), откатываемся на обычные UserDefaults.
    static let appGroupID = "group.com.bogdan.Gamer-s-Calendar"

    private let defaults: UserDefaults
    private let storageKey = "trackedGames"

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard

        // Переносим список из старого хранилища (до появления App Group).
        if defaults.data(forKey: storageKey) == nil,
           let legacy = UserDefaults.standard.data(forKey: storageKey) {
            defaults.set(legacy, forKey: storageKey)
        }
    }

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
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func hasReminder(for gameID: Int) -> Bool {
        trackedGames.contains { $0.id == gameID }
    }

    /// Включает напоминание. Возвращает false, если пользователь
    /// не дал разрешение на уведомления.
    func addReminder(for game: GamesStorage) async -> Bool {
        guard game.releaseDate != nil else { return false }

        let center = UNUserNotificationCenter.current()
        let authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard authorized else { return false }

        await scheduleNotification(for: game)
        trackedGames = trackedGames.filter { $0.id != game.id } + [game]
        return true
    }

    func removeReminder(for gameID: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID(for: gameID)])
        trackedGames = trackedGames.filter { $0.id != gameID }
    }

    /// Сверяет сохранённые игры с IGDB: даты релизов часто переносят.
    /// Обновляет снимки и уведомления, возвращает id игр с изменившейся датой.
    func refreshReleaseDates(using service: IGDBService) async -> Set<Int> {
        let tracked = trackedGames
        guard !tracked.isEmpty,
              let fresh = try? await service.fetchGames(ids: tracked.map(\.id)) else {
            return []
        }

        var changedIDs = Set<Int>()
        let updated = tracked.map { game -> GamesStorage in
            guard let freshGame = fresh.first(where: { $0.id == game.id }) else { return game }

            if freshGame.releaseDate != game.releaseDate {
                changedIDs.insert(game.id)
            }
            return freshGame
        }

        if !changedIDs.isEmpty {
            trackedGames = updated
            for game in updated where changedIDs.contains(game.id) {
                await scheduleNotification(for: game)
            }
        }

        return changedIDs
    }

    /// Ставит (или переставляет) уведомление на утро дня релиза.
    private func scheduleNotification(for game: GamesStorage) async {
        guard let releaseDate = game.releaseDate else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: game.id)])

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
    }

    private func notificationID(for gameID: Int) -> String {
        "game-release-\(gameID)"
    }

}
