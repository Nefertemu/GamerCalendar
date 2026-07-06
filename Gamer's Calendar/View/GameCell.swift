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
        releaseDateLabel.text = game.releaseDate?.formatted(date: .abbreviated, time: .omitted) ?? String(localized: "Unknown date")

        showPlatformIcons(game.platformBadges)
        loadImage(from: game.imageURL)
    }

    /// Рисует иконки платформ внутри лейбла через NSTextAttachment.
    private func showPlatformIcons(_ badges: [PlatformBadge]) {
        guard !badges.isEmpty else {
            platformsLabel.text = String(localized: "Unknown platform")
            return
        }

        let config = UIImage.SymbolConfiguration(pointSize: platformsLabel.font.pointSize, weight: .regular)
        let text = NSMutableAttributedString()

        for (index, badge) in badges.enumerated() {
            // Фирменные логотипы появились не во всех версиях iOS —
            // на старых системах показываем нейтральный геймпад.
            let image = UIImage(systemName: badge.symbolName, withConfiguration: config)
                ?? UIImage(systemName: "gamecontroller", withConfiguration: config)
            let attachment = NSTextAttachment()
            attachment.image = image?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            text.append(NSAttributedString(attachment: attachment))

            if index < badges.count - 1 {
                text.append(NSAttributedString(string: "  "))
            }
        }

        platformsLabel.attributedText = text
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
