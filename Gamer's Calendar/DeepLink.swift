import Foundation
import CoreSpotlight

enum GameDeepLink {

    static func gameID(from url: URL) -> Int? {
        guard url.scheme == "gamercalendar", url.host == "game" else { return nil }
        return Int(url.lastPathComponent)
    }

    static func gameID(from userActivity: NSUserActivity) -> Int? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("game-") else {
            return nil
        }
        return Int(identifier.dropFirst("game-".count))
    }

}
