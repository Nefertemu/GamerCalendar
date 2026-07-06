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

    func configure(with game: GamesStorage, showCountdown: Bool = false) {
        gameTitleLabel.text = game.gameTitle
        releaseDateLabel.text = releaseDateText(for: game.releaseDate, showCountdown: showCountdown)

        showPlatformIcons(game.platformBadges)
        loadImage(from: game.imageURL)
    }

    private func releaseDateText(for releaseDate: Date?, showCountdown: Bool) -> String {
        guard let releaseDate else { return String(localized: "Unknown date") }

        let dateText = releaseDate.formatted(date: .abbreviated, time: .omitted)
        guard showCountdown else { return dateText }

        if releaseDate <= .now {
            return "\(dateText) · \(String(localized: "Released!"))"
        }
        // «Через 3 дня» — системный форматтер, локализуется сам.
        return "\(dateText) · \(releaseDate.formatted(.relative(presentation: .numeric)))"
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
