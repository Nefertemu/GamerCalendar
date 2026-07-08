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

    /// Подложка для портретных постеров: та же картинка на весь слот + блюр.
    private let backdropImageView = UIImageView()
    private let backdropBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))

    /// ID текущей игры. Используется как токен, чтобы не подставить
    /// в переиспользованную ячейку картинку от предыдущей игры.
    private var currentGameID: Int?

    override func awakeFromNib() {
        super.awakeFromNib()

        gameImageView.contentMode = .scaleAspectFill
        gameImageView.clipsToBounds = true
        gameImageView.layer.cornerRadius = 12
        gameImageView.backgroundColor = .secondarySystemFill
        gameImageView.tintColor = .tertiaryLabel

        backdropImageView.contentMode = .scaleAspectFill
        backdropImageView.clipsToBounds = true
        backdropImageView.layer.cornerRadius = 12
        backdropImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(backdropImageView, belowSubview: gameImageView)

        backdropBlurView.clipsToBounds = true
        backdropBlurView.layer.cornerRadius = 12
        backdropBlurView.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(backdropBlurView, aboveSubview: backdropImageView)

        NSLayoutConstraint.activate([
            backdropImageView.topAnchor.constraint(equalTo: gameImageView.topAnchor),
            backdropImageView.bottomAnchor.constraint(equalTo: gameImageView.bottomAnchor),
            backdropImageView.leadingAnchor.constraint(equalTo: gameImageView.leadingAnchor),
            backdropImageView.trailingAnchor.constraint(equalTo: gameImageView.trailingAnchor),

            backdropBlurView.topAnchor.constraint(equalTo: gameImageView.topAnchor),
            backdropBlurView.bottomAnchor.constraint(equalTo: gameImageView.bottomAnchor),
            backdropBlurView.leadingAnchor.constraint(equalTo: gameImageView.leadingAnchor),
            backdropBlurView.trailingAnchor.constraint(equalTo: gameImageView.trailingAnchor)
        ])
        setBackdropHidden(true)

        // «19 нояб. 2026 г. · через 4 мес.» — длинная строка, ужимаем при нужде.
        releaseDateLabel.adjustsFontSizeToFitWidth = true
        releaseDateLabel.minimumScaleFactor = 0.75
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        currentGameID = nil
        showPlaceholder()
    }

    func configure(with game: GamesStorage, showCountdown: Bool = false, dateChanged: Bool = false) {
        gameTitleLabel.text = game.gameTitle
        releaseDateLabel.text = releaseDateText(for: game.releaseDate, showCountdown: showCountdown, dateChanged: dateChanged)
        releaseDateLabel.textColor = dateChanged ? .systemOrange : .secondaryLabel

        showPlatformIcons(game.platformBadges)
        loadPoster(for: game)
    }

    private func releaseDateText(for releaseDate: Date?, showCountdown: Bool, dateChanged: Bool) -> String {
        guard let releaseDate else { return String(localized: "Unknown date") }

        let dateText = releaseDate.formatted(date: .abbreviated, time: .omitted)

        if dateChanged {
            return "\(dateText) · \(String(localized: "New date!"))"
        }
        guard showCountdown else { return dateText }

        if releaseDate <= .now {
            return "\(dateText) · \(String(localized: "Released!"))"
        }
        // «Через 3 дня» — системный форматтер, локализуется сам.
        // Narrow-стиль («через 4 мес.»), чтобы строка влезала в ячейку.
        return "\(dateText) · \(releaseDate.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))"
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

    // MARK: - Постер

    private func loadPoster(for game: GamesStorage) {
        currentGameID = game.id
        showPlaceholder()

        // Мгновенный путь: выбранный ранее арт уже в памяти.
        for url in game.artworkURLs ?? [] {
            if let cached = ImageCache.shared.image(for: url) {
                apply(cached)
                return
            }
        }

        // Кэш обложки и скриншота используем только когда артов нет вовсе:
        // иначе прогретая сеткой портретная обложка перебьёт альбомный арт.
        if (game.artworkURLs ?? []).isEmpty {
            for url in game.posterCandidates {
                if let cached = ImageCache.shared.image(for: url) {
                    apply(cached)
                    return
                }
            }
        }

        Task {
            guard let image = await ImageCache.shared.loadPoster(for: game) else { return }
            // Применяем картинку только если ячейку не переиспользовали под другую игру.
            guard currentGameID == game.id else { return }
            apply(image)
        }
    }

    /// Постер показывается целиком (свободное место добивает размытая копия) —
    /// у большинства артов логотип доходит до краёв, и кроп его режет.
    /// Исключение — сверхширокие панорамы: целиком они превращаются
    /// в тонкую полоску, им лучше кроп по центру.
    private func apply(_ image: UIImage) {
        let aspect = image.size.width / max(image.size.height, 1)

        if aspect > 2.2 {
            gameImageView.contentMode = .scaleAspectFill
            gameImageView.backgroundColor = .secondarySystemFill
            setBackdropHidden(true)
        } else {
            gameImageView.contentMode = .scaleAspectFit
            gameImageView.backgroundColor = .clear
            backdropImageView.image = image
            setBackdropHidden(false)
        }

        gameImageView.image = image
    }

    private func showPlaceholder() {
        gameImageView.contentMode = .scaleAspectFill
        gameImageView.backgroundColor = .secondarySystemFill
        gameImageView.image = UIImage(systemName: "photo")
        setBackdropHidden(true)
    }

    private func setBackdropHidden(_ hidden: Bool) {
        backdropImageView.isHidden = hidden
        backdropBlurView.isHidden = hidden
        if hidden {
            backdropImageView.image = nil
        }
    }

}
