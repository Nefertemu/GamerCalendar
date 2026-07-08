
import Foundation
import UserNotifications
import WidgetKit
import CoreSpotlight

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
            reindexSpotlight(sorted)
        }
    }

    /// Отслеживаемые игры ищутся из системного поиска iPhone.
    private func reindexSpotlight(_ games: [GamesStorage]) {
        let items = games.map { game -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = game.gameTitle
            if let releaseDate = game.releaseDate {
                attributes.contentDescription = String(localized: "Releases \(releaseDate.formatted(date: .long, time: .omitted))")
            }
            return CSSearchableItem(
                uniqueIdentifier: "game-\(game.id)",
                domainIdentifier: "trackedGames",
                attributeSet: attributes
            )
        }

        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: ["trackedGames"]) { _ in
            index.indexSearchableItems(items)
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

        if let attachment = await imageAttachment(for: game) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: notificationID(for: game.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    /// Постер игры для уведомления: iOS требует файл на диске,
    /// поэтому скачиваем и кладём во временную папку.
    private func imageAttachment(for game: GamesStorage) async -> UNNotificationAttachment? {
        guard let imageURL = game.imageURL,
              let (data, _) = try? await URLSession.shared.data(from: imageURL) else {
            return nil
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-\(game.id).jpg")

        do {
            try data.write(to: fileURL)
            return try UNNotificationAttachment(identifier: "cover", url: fileURL)
        } catch {
            return nil
        }
    }

    private func notificationID(for gameID: Int) -> String {
        "game-release-\(gameID)"
    }

    // MARK: - Еженедельный дайджест

    /// Ставит уведомление на ближайший понедельник 10:00 со списком
    /// отслеживаемых игр, выходящих на той неделе. Вызывается при каждом
    /// запуске — содержимое пересчитывается заново.
    func scheduleWeeklyDigest() {
        let digestID = "weekly-digest"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [digestID])

        let calendar = Calendar.current
        var mondayComponents = DateComponents(hour: 10, weekday: 2)

        guard let nextMonday = calendar.nextDate(
            after: .now,
            matching: mondayComponents,
            matchingPolicy: .nextTime
        ) else { return }

        // Игры, выходящие в течение недели после дайджеста.
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: nextMonday) else { return }
        let releasing = trackedGames.filter { game in
            guard let date = game.releaseDate else { return false }
            return date >= nextMonday && date < weekEnd
        }
        guard !releasing.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "This week's releases")
        content.body = releasing.map(\.gameTitle).joined(separator: ", ")
        content.sound = .default

        mondayComponents = calendar.dateComponents([.year, .month, .day, .hour], from: nextMonday)

        let request = UNNotificationRequest(
            identifier: digestID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: mondayComponents, repeats: false)
        )
        center.add(request)
    }

}
