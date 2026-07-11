# Gamer Calendar

Gamer Calendar is an iOS release tracker for video games. It combines an upcoming-games feed, a real calendar grid, a watchlist, release reminders, widgets, Live Activities, and richer IGDB metadata such as platform-specific release dates.

Built with **UIKit**, **WidgetKit / SwiftUI**, **ActivityKit**, **Swift Concurrency**, and the **[IGDB API](https://api-docs.igdb.com/)** through Twitch OAuth.

## Highlights

- Upcoming game feed with search, filters, sorting, pagination, and month grouping.
- Calendar grid with release posters, day sheets, swipe navigation, Today shortcut, loading/error states, and month transition animation.
- Watchlist with release countdowns, release-date refresh, local notifications, weekly digest, Spotlight indexing, and swipe-to-remove.
- Game details with trailer, screenshots, rating, description, genres, developers, store links, franchise navigation, similar games, and IGDB page link.
- Release intelligence: platform-specific release dates, release-date accuracy, preorder availability, and update badges.
- Home screen widget and Live Activity / Dynamic Island countdown for tracked releases.
- Offline-first catalog cache and disk-backed image cache.
- English and Russian localization via String Catalogs.

## Features

### Browse Releases

- **Feed**: upcoming games grouped by month, with infinite scroll and pull-to-refresh.
- **Search**: debounced search across upcoming releases.
- **Filters**: platform family, genre, date window, and hype/date sorting.
- **Calendar**: month grid with posters on release days; tap a day to see every release in a sheet.
- **Fast reloads**: loaded months and catalog responses are cached, so returning to already visited data is quick.

### Track Games

- **Watchlist**: tap the bell on a game page to track it.
- **Reminder presets**: release day, 1 day before, and 7 days before.
- **Weekly digest**: Monday notification with tracked games releasing that week.
- **Date-change handling**: tracked games are refreshed against IGDB; if a release date moves, the app updates the snapshot and reschedules notifications.
- **Update badges**: watchlist rows can surface useful status such as preorder availability or non-final release dates.

### Game Details

- **Media**: trailer, screenshots, zoomable screenshot viewer, and stretchy header image.
- **Metadata**: description, genres, developers, rating, platforms, similar games, and franchise page.
- **Links**: Steam, PlayStation Store, Xbox Store, Nintendo eShop, Epic Games, GOG, official site, and IGDB page where available.
- **Release Status**: shows whether the date is exact, month-only, year-only, quarter-based, TBA, or unknown.
- **Platform Release Dates**: groups equal dates together, for example:

```text
Feb 18, 2027 · Advanced Access: PC, PlayStation 5, Xbox Series X|S
Feb 23, 2027 · Full Release: PC, PlayStation 5, Xbox Series X|S
```

### Widgets and Live Activities

- **Home screen widget**: small and medium widgets for upcoming tracked games.
- **Deep links**: widgets and Spotlight results open directly into the game page.
- **Live Activity**: Lock Screen and Dynamic Island countdown. The compact island uses short countdown text such as `4mo` instead of a long hour timer.

### Offline and Data Quality

- **Offline catalog cache**: feed pages, calendar months, details, franchise lists, and ID lookups fall back to cached JSON when the network fails.
- **Image cache**: disk-backed image loading reduces repeated downloads.
- **Smart poster selection**: IGDB can return blank or low-value artwork; the app compares thumbnail content and falls back through artwork, screenshots, and covers.
- **Landscape/portrait handling**: list cells prefer landscape art; calendar cells use portrait covers.

## Setup

1. Clone the repo.
2. Open `Gamer's Calendar.xcodeproj` in Xcode.
3. Create a Twitch application at [dev.twitch.tv/console](https://dev.twitch.tv/console). IGDB uses Twitch OAuth.
4. Copy:

```sh
cp "Gamer's Calendar/Secrets.example.swift" "Gamer's Calendar/Secrets.swift"
```

5. Fill `Secrets.swift` with your Twitch Client ID and Client Secret.
6. Build and run.

`Secrets.swift` is ignored by git. Do not commit real credentials.

## Architecture

- `Model/Games.swift`: domain models, release-date accuracy models, filters, and first-page cache.
- `Model/IGDBService.swift`: IGDB response models, Apicalypse query building, Twitch token refresh, response mapping, store-link filtering, and release-date intelligence.
- `Model/ImageCache.swift`: disk-backed image loading, poster candidate fallback, placeholder rejection, and artwork quality selection.
- `Model/GameCatalogService.swift`: catalog abstraction used by screens and tests.
- `Model/CachedGameCatalogService.swift`: offline-first wrapper around IGDB.
- `Model/ReminderService.swift`: watchlist storage, App Group sync, notifications, weekly digest, and Spotlight indexing.
- `Model/ReleaseCountdown.swift`: Live Activity attributes and start logic.
- `TableViewController.swift`: release feed, search, filters, sorting, pagination, and empty/error states.
- `MonthGridViewController.swift`: calendar grid, month cache, day release sheet, and animated month transitions.
- `WatchlistViewController.swift`: tracked releases, countdowns, refresh of moved dates, and update badges.
- `GameDetailViewController.swift`: game page assembled with UIKit stack views.
- `FranchiseViewController.swift`: games from the same franchise.
- `GamerCalendarWidget/`: WidgetKit extension and Live Activity UI.

## API Notes

The app uses IGDB v4 with Apicalypse queries.

- `games` is used for feed pages, calendar months, watchlist refreshes, franchise pages, and details.
- `release_dates` is used to show platform-specific dates and release accuracy.
- `websites` is used for store links and preorder availability signals.
- `videos`, `screenshots`, `similar_games`, `franchises`, `genres`, and `involved_companies` power the detail screen.

Search uses `name ~ *"..."*` instead of IGDB's `search` operator so feed sorting stays predictable.

## App Store Notes

- The app includes privacy manifests for the main app and widget extension.
- `ITSAppUsesNonExemptEncryption` is set to `false`.
- App Group is used for watchlist sharing between the app and widget.
- The App Store privacy labels should match the actual shipped behavior. If analytics, external price APIs, or tracking are added later, update privacy labels and `PrivacyInfo.xcprivacy`.
- Third-party game artwork and metadata come from IGDB; App Store metadata should include appropriate attribution and usage notes where required.

## Tests

The project includes Swift Testing coverage for:

- IGDB game mapping.
- Platform badge mapping.
- Store link filtering.
- Month grouping.
- Reminder date refresh behavior.
- Deep link parsing.

Run tests from Xcode. CLI simulator tests may require a matching installed simulator runtime/destination.

## Roadmap

- [ ] PC price tracking through IsThereAnyDeal or CheapShark.
- [ ] Price-drop alerts for watchlisted games.
- [ ] Better release history: show moved-from / moved-to dates.
- [ ] Event calendar for showcases such as Nintendo Direct, State of Play, Gamescom, and The Game Awards.
- [ ] More widget variants: this-week releases, watchlist calendar, and price drops.
- [ ] iPad layout with split view.
- [ ] UI tests for feed, calendar, watchlist, deep links, and settings.
- [ ] README screenshots and App Store-style preview images.
