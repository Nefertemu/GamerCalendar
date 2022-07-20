
import UIKit

struct GamesStorage {
    let gameTitle: String
    let image: UIImage
    let releaseDate: Date
    let platforms: String
}

var games = [
    GamesStorage(gameTitle: "Starfield",
                 image: UIImage(named: "starfield")!,
                 releaseDate: Date(timeIntervalSinceReferenceDate: 689877015),
                 platforms: "PC, PlayStation 5, Xbox Series"),
    GamesStorage(gameTitle: "The Elder Scrolls VI",
                 image: UIImage(named: "tes")!,
                 releaseDate: Date(timeIntervalSinceReferenceDate: 757442166),
                 platforms: "PC, PlayStation 5, Xbox Series"),
    GamesStorage(gameTitle: "Forza Motorsport 8",
                 image: UIImage(named: "forza")!,
                 releaseDate: Date(timeIntervalSinceReferenceDate: 686334966),
                 platforms: "PC, PlayStation 5, Xbox Series"),
    GamesStorage(gameTitle: "Hogwards legacy",
                 image: UIImage(named: "hogwards")!,
                 releaseDate: Date(timeIntervalSinceReferenceDate: 691605366),
                 platforms: "PC, PlayStation 5, Xbox Series")
]


