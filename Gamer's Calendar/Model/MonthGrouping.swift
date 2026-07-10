
import Foundation

/// Секция ленты: игры одного месяца.
struct MonthSection {
    let month: Date
    var games: [GamesStorage]
}

/// Группировка отсортированного по дате списка игр в секции-месяцы.
enum MonthGrouper {

    /// Добавляет игры в конец существующих секций. Список приходит
    /// по возрастанию даты релиза, поэтому продолжается либо последняя
    /// секция, либо открывается новая; игры без даты пропускаются.
    static func append(_ games: [GamesStorage], to sections: inout [MonthSection], calendar: Calendar = .current) {
        for game in games {
            guard let date = game.releaseDate else { continue }

            if let lastIndex = sections.indices.last,
               calendar.isDate(sections[lastIndex].month, equalTo: date, toGranularity: .month) {
                sections[lastIndex].games.append(game)
            } else {
                let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
                sections.append(MonthSection(month: month, games: [game]))
            }
        }
    }

}
