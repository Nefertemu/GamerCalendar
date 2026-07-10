# Gamer Calendar

iOS app that tracks upcoming video game releases. Browse what's coming out in a feed or on a real calendar grid, follow the games you care about, and get notified on release day — with a home screen widget and a Dynamic Island countdown.

Built with **UIKit**, **SwiftUI (widget)**, **Swift Concurrency (async/await)**, and the **[IGDB API](https://api-docs.igdb.com/)** (via Twitch OAuth).

## Features

### Browsing
- 📅 **Release feed** — upcoming games grouped by month with infinite scrolling, pull-to-refresh, detailed error states, and a navigation title that follows the month you're scrolling through.
- 🗓 **Calendar grid** — a real month view with game posters on release days, loading/error/empty states, swipe navigation, and a Today shortcut. Tap a day to see its releases in a sheet. Months switch instantly: adjacent months and their posters are prefetched in the background.
- 🔍 **Search** — debounced search across upcoming releases.
- 🎛 **Filters & sorting** — platform family (PC / PlayStation / Xbox / Nintendo), date window from 3 months to 5 years, sort by release date or by hype. Selected filters persist across launches.

### Tracking
- 🔔 **Watchlist** — track games with one tap on the bell. Release-day notification with the game poster, countdown in the list, swipe to remove.
- 📆 **Live dates** — tracked games are re-checked against IGDB: when a release date shifts, the app updates the snapshot, reschedules the notification, and highlights the change.
- 🗞 **Weekly digest** — a Monday-morning notification listing your tracked games releasing that week.
- 📱 **Home screen widget** — next tracked releases with a live countdown (small and medium sizes), fed from an App Group shared with the app.
- ⏱ **Live Activity** — countdown to a release on the Lock Screen and in the Dynamic Island.

### Game page
- 🎬 Trailer (YouTube), rating, description, genres, developers.
- 🖼 Stretchy parallax cover and a zoomable full-screen screenshot viewer.
- 🛒 Store links: Steam / PS Store / Xbox / Nintendo eShop / Epic / GOG / official site.
- 🧩 Franchise page (all games of the series) and a similar-games strip with drill-down navigation.

### Under the hood
- 🖼 **Smart poster picking** — IGDB artworks include blank and placeholder files, so the app compares artwork thumbnail sizes and picks the most detailed poster; portrait covers are used in the calendar grid, landscape artworks in lists.
- ⚡️ **Fast launch** — the first page is cached on disk and shown instantly while fresh data loads; images use a disk-backed cache.
- 🌍 **Localization** — English and Russian via String Catalogs, including proper plural forms.
- ✅ **Unit tests** for the IGDB response mapping (Swift Testing).

## Setup

1. Clone the repo and open `Gamer's Calendar.xcodeproj`.
2. Create a Twitch application at [dev.twitch.tv/console](https://dev.twitch.tv/console) (IGDB uses Twitch OAuth) and copy its Client ID and Client Secret.
3. Copy `Gamer's Calendar/Secrets.example.swift` to `Gamer's Calendar/Secrets.swift` and fill in the Twitch Client ID and Client Secret. `Secrets.swift` is gitignored; do not commit real credentials.

4. Build and run.

## Architecture

- `Model/Games.swift` — domain models (`GamesStorage`, `GameDetails`), the `IGDBService` network layer (token refresh, Apicalypse query building, response mapping), image cache with artwork quality selection, first-page cache.
- `Model/ReminderService.swift` — watchlist storage (App Group `UserDefaults`, shared with the widget), release notifications, weekly digest.
- `Model/ReleaseCountdown.swift` — Live Activity attributes and start logic.
- `TableViewController` — release feed: month sections, search, filters, pagination, detailed error/empty states.
- `MonthGridViewController` — calendar grid with month cache and adjacent-month prefetch.
- `WatchlistViewController` — tracked games with countdowns and date-change refresh.
- `GameDetailViewController` — game page assembled from stack views.
- `FranchiseViewController` — games of a franchise.
- `GamerCalendarWidget/` — WidgetKit extension: home screen widget and Live Activity UI.

## API notes

The app talks to IGDB v4 (`/games` endpoint with the Apicalypse query language). The Twitch OAuth token is requested lazily and refreshed automatically before expiry. Search uses a `name ~ *"…"*` filter instead of IGDB's `search` so results stay sorted by release date. The image CDN doesn't expose file sizes, so artwork quality is compared via thumbnail downloads.

## Roadmap

- [ ] Interactive widget controls
- [ ] Universal links for shared games
- [ ] iPad layout (split view) and Mac Catalyst
- [ ] UI tests for feed, calendar, watchlist, and deep links
- [ ] Screenshots in this README
