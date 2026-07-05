//
//  GameCell.swift
//  Gamer's Calendar
//
//  Created by Богдан Анищенков on 04.05.2022.
//

import UIKit

class GameCell: UITableViewCell {

    @IBOutlet var gameImageView: UIImageView!
    @IBOutlet var gameTitleLabel: UILabel!
    @IBOutlet var releaseDateLabel: UILabel!
    @IBOutlet var platformsLabel: UILabel!

    /// URL текущей игры. Используется как токен, чтобы не подставить
    /// в переиспользованную ячейку картинку от предыдущей игры.
    private var currentImageURL: URL?

    override func awakeFromNib() {
        super.awakeFromNib()

        gameImageView.contentMode = .scaleAspectFill
        gameImageView.clipsToBounds = true
        gameImageView.layer.cornerRadius = 12
        gameImageView.backgroundColor = .secondarySystemFill
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        currentImageURL = nil
        gameImageView.image = UIImage(systemName: "photo")
    }

    func configure(with game: GamesStorage) {
        gameTitleLabel.text = game.gameTitle
        platformsLabel.text = game.platforms.isEmpty ? "Unknown platform" : game.platforms
        releaseDateLabel.text = game.releaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date"

        loadImage(from: game.imageURL)
    }

    private func loadImage(from url: URL?) {
        currentImageURL = url

        guard let url else {
            gameImageView.image = UIImage(systemName: "photo")
            return
        }

        if let cached = ImageCache.shared.image(for: url) {
            gameImageView.image = cached
            return
        }

        gameImageView.image = UIImage(systemName: "photo")

        Task {
            guard let image = await ImageCache.shared.loadImage(from: url) else { return }
            // Применяем картинку только если ячейку не переиспользовали под другую игру.
            guard currentImageURL == url else { return }
            gameImageView.image = image
        }
    }

}
