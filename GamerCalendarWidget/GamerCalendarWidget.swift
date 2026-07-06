
import WidgetKit
import SwiftUI

/// Снимок игры из общего хранилища (App Group), которое пишет приложение.
/// Поля повторяют GamesStorage — лишние ключи при декодировании игнорируются.
struct WidgetGame: Decodable, Identifiable {
    let id: Int
    let gameTitle: String
    let releaseDate: Date?
}

struct NextReleaseEntry: TimelineEntry {
    let date: Date
    let games: [WidgetGame]
}

struct NextReleaseProvider: TimelineProvider {

    func placeholder(in context: Context) -> NextReleaseEntry {
        NextReleaseEntry(date: .now, games: [
            WidgetGame(id: 1, gameTitle: "Grand Theft Auto VI", releaseDate: .now.addingTimeInterval(86400 * 42))
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (NextReleaseEntry) -> Void) {
        completion(NextReleaseEntry(date: .now, games: loadGames()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextReleaseEntry>) -> Void) {
        let entry = NextReleaseEntry(date: .now, games: loadGames())
        // Обновляемся раз в час; сам отсчёт дней iOS пересчитывает на лету.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func loadGames() -> [WidgetGame] {
        guard let defaults = UserDefaults(suiteName: "group.com.bogdan.Gamer-s-Calendar"),
              let data = defaults.data(forKey: "trackedGames"),
              let games = try? JSONDecoder().decode([WidgetGame].self, from: data) else {
            return []
        }
        return games
            .filter { ($0.releaseDate ?? .distantPast) > .now }
            .sorted { ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture) }
    }

}

struct NextReleaseWidgetView: View {

    @Environment(\.widgetFamily) private var family
    var entry: NextReleaseEntry

    var body: some View {
        Group {
            if entry.games.isEmpty {
                emptyView
            } else if family == .systemMedium {
                mediumView
            } else {
                smallView
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.29, green: 0.13, blue: 0.6), Color(red: 0.07, green: 0.08, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.badge")
                .font(.title2)
            Text("Add games to your watchlist")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "gamecontroller.fill")
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(entry.games[0].gameTitle)
                .font(.headline)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let date = entry.games[0].releaseDate {
                // style: .relative — живой отсчёт, обновляется сам.
                Text(date, style: .relative)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entry.games.prefix(3)) { game in
                HStack(alignment: .firstTextBaseline) {
                    Text(game.gameTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    if let date = game.releaseDate {
                        Text(date, style: .relative)
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

}

struct GamerCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextReleaseWidget", provider: NextReleaseProvider()) { entry in
            NextReleaseWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Releases")
        .description("Countdown to the games you track.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
