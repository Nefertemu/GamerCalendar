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

    private let statusLabel = UILabel()

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

        // «19 Sep 2026 · 2 mo» — длинная строка, ужимаем при нужде.
        releaseDateLabel.allowsDefaultTighteningForTruncation = true
        releaseDateLabel.adjustsFontSizeToFitWidth = true
        releaseDateLabel.minimumScaleFactor = 0.6

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .systemOrange
        statusLabel.numberOfLines = 1
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: platformsLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: platformsLabel.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: platformsLabel.bottomAnchor, constant: 2)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        currentGameID = nil
        statusLabel.text = nil
        showPlaceholder()
    }

    func configure(with game: GamesStorage, showCountdown: Bool = false, dateChanged: Bool = false, statusBadge: String? = nil, prefersPortraitPoster: Bool = false, excludesPortraitFallback: Bool = false) {
        gameTitleLabel.text = game.gameTitle
        releaseDateLabel.text = releaseDateText(for: game.releaseDate, showCountdown: showCountdown, dateChanged: dateChanged)
        releaseDateLabel.textColor = dateChanged ? .systemOrange : .secondaryLabel
        statusLabel.text = statusBadge?.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.isHidden = (statusLabel.text ?? "").isEmpty

        showPlatformIcons(game.platformBadges)
        loadPoster(for: game, prefersPortraitPoster: prefersPortraitPoster, excludesPortraitFallback: excludesPortraitFallback)
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
        return "\(dateText) · \(compactCountdownText(until: releaseDate))"
    }

    private func compactCountdownText(until releaseDate: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.startOfDay(for: releaseDate)
        let components = calendar.dateComponents([.year, .month, .day], from: start, to: end)

        if let years = components.year, years > 0 {
            return "\(years)y"
        }
        if let months = components.month, months > 0 {
            return "\(months)mo"
        }

        let days = max(components.day ?? 0, 1)
        return "\(days)d"
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

    private func loadPoster(for game: GamesStorage, prefersPortraitPoster: Bool, excludesPortraitFallback: Bool) {
        currentGameID = game.id
        showPlaceholder()

        if prefersPortraitPoster {
            for url in game.portraitPosterCandidates {
                if let cached = ImageCache.shared.image(for: url) {
                    apply(cached)
                    return
                }
            }

            Task {
                guard let image = await ImageCache.shared.loadImage(fromCandidates: game.portraitPosterCandidates) else { return }
                guard currentGameID == game.id else { return }
                apply(image)
            }
            return
        }

        if excludesPortraitFallback {
            Task {
                guard let image = await ImageCache.shared.loadPoster(for: game, includesPortraitFallback: false) else { return }
                guard currentGameID == game.id else { return }
                apply(image)
            }
            return
        }

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
        gameImageView.image = nil
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
