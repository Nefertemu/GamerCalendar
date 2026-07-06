# Gamer Calendar

iOS app that tracks upcoming video game releases. Browse what's coming out, follow the games you care about, and get notified on release day.

Built with **UIKit**, **Swift Concurrency (async/await)**, and the **[IGDB API](https://api-docs.igdb.com/)** (via Twitch OAuth).

## Features

- 📅 **Release calendar** — upcoming games grouped by month, with infinite scrolling and pull-to-refresh. The navigation title follows the month you're scrolling through.
- 🔍 **Search** — debounced search across upcoming releases.
- 🎛 **Filters & sorting** — filter by platform family (PC / PlayStation / Xbox / Nintendo), sort by release date or by hype (most anticipated).
- 🔔 **Watchlist** — track games with one tap on the bell. Local notification on release morning, countdown in the list, swipe to remove.
- 📆 **Live dates** — tracked games are re-checked against IGDB, so when a release date shifts, the app updates the snapshot, reschedules the notification, and highlights the change.
- 🎬 **Game details** — trailer (YouTube), rating, description, genres, developers, screenshots with a zoomable full-screen viewer, store links (Steam / PS Store / Xbox / Nintendo eShop / Epic / GOG), and a similar-games strip with drill-down navigation.
- ⚡️ **Fast launch** — the first page is cached on disk and shown instantly while fresh data loads; images use a disk-backed cache.
- 🌍 **Localization** — English and Russian via String Catalogs, including proper plural forms.

## Setup

1. Clone the repo and open `Gamer's Calendar.xcodeproj`.
2. Create a Twitch application at [dev.twitch.tv/console](https://dev.twitch.tv/console) (IGDB uses Twitch OAuth) and copy its Client ID and Client Secret.
3. Create `Gamer's Calendar/Secrets.swift` (the file is gitignored):

```swift
import Foundation

enum Secrets {
    static let igdbClientID = "your-client-id"
    static let igdbClientSecret = "your-client-secret"
}
```

4. Build and run.

## Architecture

- `Model/Games.swift` — domain models (`GamesStorage`, `GameDetails`), the `IGDBService` network layer (token refresh, query building, response mapping), image and first-page caches.
- `Model/ReminderService.swift` — watchlist storage (App Group `UserDefaults`) and local notifications.
- `TableViewController` — release calendar: month sections, search, filters, pagination, error/empty states.
- `WatchlistViewController` — tracked games with countdowns and date-change refresh.
- `GameDetailViewController` — game page assembled from stack views.
- Unit tests cover IGDB response mapping (`Gamer's CalendarTests`).

## API notes

The app talks to IGDB v4 (`/games` endpoint with the Apicalypse query language). The Twitch OAuth token is requested lazily and refreshed automatically before expiry. Search uses a `name ~ *"…"*` filter instead of IGDB's `search` so results stay sorted by release date.
