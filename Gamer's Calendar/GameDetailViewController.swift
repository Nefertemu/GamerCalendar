
import UIKit
import SafariServices

/// Экран с подробной информацией об игре: обложка, трейлер, описание,
/// жанры, разработчики, скриншоты, ссылки и похожие игры.
class GameDetailViewController: UIViewController {

    private let game: GamesStorage
    private let gameService: GameCatalogService

    private let contentStack = UIStackView()
    private let detailsStack = UIStackView()
    private let coverImageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var screenshotURLs: [URL] = []
    private var similarGames: [GamesStorage] = []
    private var pageURL: URL?
    private var isBuildingDetails = false

    init(game: GamesStorage, gameService: GameCatalogService) {
        self.game = game
        self.gameService = gameService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        setupLayout()
        showBasicInfo()
        loadDetails()
        updateReminderButton()
    }

    // MARK: - Напоминание о релизе

    private func updateReminderButton() {
        let hasReminder = ReminderService.shared.hasReminder(for: game.id)
        var buttons = [UIBarButtonItem(
            image: UIImage(systemName: hasReminder ? "bell.fill" : "bell"),
            primaryAction: UIAction { [weak self] _ in self?.toggleReminder() }
        )]

        // Отсчёт до релиза на экране блокировки (Live Activity).
        if #available(iOS 16.2, *), let releaseDate = game.releaseDate, releaseDate > .now {
            buttons.append(UIBarButtonItem(
                image: UIImage(systemName: "timer"),
                primaryAction: UIAction { [weak self] _ in self?.startCountdown() }
            ))
        }

        buttons.append(UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.shareGame() }
        ))

        navigationItem.rightBarButtonItems = buttons
    }

    private func shareGame() {
        let dateText = game.releaseDate?.formatted(date: .long, time: .omitted) ?? ""
        let text = String(localized: "\(game.gameTitle) — releases \(dateText). Tracking with Gamer Calendar!")

        var items: [Any] = [text]
        if let pageURL {
            items.append(pageURL)
        }

        present(UIActivityViewController(activityItems: items, applicationActivities: nil), animated: true)
    }

    @available(iOS 16.2, *)
    private func startCountdown() {
        let started = ReleaseCountdown.start(for: game)

        let alert = UIAlertController(
            title: started
                ? String(localized: "Countdown started")
                : String(localized: "Couldn't start countdown"),
            message: started
                ? String(localized: "Check your Lock Screen and Dynamic Island.")
                : String(localized: "Live Activities are disabled in Settings."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func toggleReminder() {
        if ReminderService.shared.hasReminder(for: game.id) {
            ReminderService.shared.removeReminder(for: game.id)
            updateReminderButton()
        } else {
            Task {
                let added = await ReminderService.shared.addReminder(for: game)
                if !added {
                    showNotificationsDeniedAlert()
                }
                updateReminderButton()
            }
        }
    }

    private func showNotificationsDeniedAlert() {
        let alert = UIAlertController(
            title: String(localized: "Notifications are off"),
            message: String(localized: "Allow notifications in Settings to get release reminders."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Open Settings"), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Layout

    private func setupLayout() {
        let scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        detailsStack.axis = .vertical
        detailsStack.spacing = 16

        let contentWidth = contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        contentWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            contentWidth,
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 760)
        ])
    }

    // MARK: - Базовая информация (доступна сразу из списка)

    private func showBasicInfo() {
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.backgroundColor = .secondarySystemFill
        coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor, multiplier: 9.0 / 16.0).isActive = true
        contentStack.addArrangedSubview(coverImageView)
        loadPoster(for: game, into: coverImageView)

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.text = game.gameTitle
        addPadded(titleLabel)

        let releaseLabel = UILabel()
        releaseLabel.font = .systemFont(ofSize: 15)
        releaseLabel.textColor = .secondaryLabel
        let dateText = game.releaseDate?.formatted(date: .long, time: .omitted) ?? String(localized: "Unknown date")
        releaseLabel.text = String(localized: "Release date: \(dateText)")
        addPadded(releaseLabel)

        if !game.platforms.isEmpty {
            addSection(header: String(localized: "Platforms"), text: game.platforms)
        }

        contentStack.addArrangedSubview(detailsStack)
        showDetailsLoading()
    }

    // MARK: - Детали из API

    private func loadDetails() {
        let gameID = game.id
        let gameService = gameService
        showDetailsLoading()

        Task { [weak self] in
            do {
                let details = try await gameService.fetchGameDetails(id: gameID)
                guard let self else { return }
                showDetails(details)
            } catch {
                guard let self else { return }
                showError(error)
                print("IGDB details loading error:", error)
            }
        }
    }

    private func showDetails(_ details: GameDetails) {
        clearDetails()
        isBuildingDetails = true
        defer { isBuildingDetails = false }

        pageURL = details.pageURL
        addRating(details)
        addReleaseStatus(details)

        if let trailerURL = details.trailerURL {
            addTrailerButton(trailerURL)
        }

        if let franchise = details.franchise {
            addFranchiseButton(franchise)
        }

        if let pageURL = details.pageURL {
            addOpenPageButton(pageURL)
        }

        if !details.about.isEmpty {
            addSection(header: String(localized: "About"), text: details.about)
        }

        if !details.updateBadges.isEmpty {
            addUpdates(details.updateBadges)
        }

        if !details.releaseDates.isEmpty {
            addPlatformReleaseDates(details.releaseDates)
        }

        if !details.genres.isEmpty {
            addSection(header: String(localized: "Genres"), text: details.genres)
        }

        if !details.developers.isEmpty {
            addSection(header: String(localized: "Developers"), text: details.developers)
        }

        if !details.screenshots.isEmpty {
            addScreenshots(details.screenshots)
        }

        if !details.links.isEmpty {
            addLinks(details.links)
        }

        if !details.similarGames.isEmpty {
            addSimilarGames(details.similarGames)
        }
    }

    // MARK: - Трейлер и ссылки

    private func addTrailerButton(_ url: URL) {
        var config = UIButton.Configuration.borderedProminent()
        config.title = String(localized: "Watch Trailer")
        config.image = UIImage(systemName: "play.fill")
        config.imagePadding = 8

        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.open(url)
        })
        addPadded(button)
    }

    private func addLinks(_ links: [GameLink]) {
        let headerLabel = UILabel()
        headerLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        headerLabel.text = String(localized: "Links")
        addPadded(headerLabel)
        contentStack.setCustomSpacing(8, after: headerLabel)

        let buttons = links.map { link in
            var config = UIButton.Configuration.bordered()
            config.title = link.title
            config.image = UIImage(systemName: "arrow.up.right.square")
            config.imagePadding = 6

            return UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
                self?.open(link.url)
            })
        }

        let linksStack = UIStackView(arrangedSubviews: buttons)
        linksStack.axis = .horizontal
        linksStack.spacing = 8
        linksStack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        linksStack.isLayoutMarginsRelativeArrangement = true

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        linksStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(linksStack)

        NSLayoutConstraint.activate([
            linksStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            linksStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            linksStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            linksStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            scrollView.heightAnchor.constraint(equalTo: linksStack.heightAnchor)
        ])

        addArranged(scrollView)
    }

    private func open(_ url: URL) {
        present(SFSafariViewController(url: url), animated: true)
    }

    private func addOpenPageButton(_ url: URL) {
        var config = UIButton.Configuration.bordered()
        config.title = String(localized: "Open on IGDB")
        config.image = UIImage(systemName: "safari")
        config.imagePadding = 8

        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.open(url)
        })
        addPadded(button)
    }

    private func addFranchiseButton(_ franchise: GameFranchise) {
        var config = UIButton.Configuration.bordered()
        config.title = String(localized: "Franchise: \(franchise.name)")
        config.image = UIImage(systemName: "square.stack.3d.up")
        config.imagePadding = 8

        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let franchiseController = FranchiseViewController(franchise: franchise, gameService: gameService)
            navigationController?.pushViewController(franchiseController, animated: true)
        })
        addPadded(button)
    }

    private func addReleaseStatus(_ details: GameDetails) {
        var lines = [String(localized: "Release confidence: \(details.releaseAccuracy.title)")]
        if details.preorderAvailable {
            lines.append(String(localized: "Preorder available"))
        }
        addSection(header: String(localized: "Release Status"), text: lines.joined(separator: "\n"))
    }

    private func addUpdates(_ badges: [GameUpdateBadge]) {
        let text = badges.map { badge in
            guard !badge.detail.isEmpty else { return "• \(badge.title)" }
            return "• \(badge.title): \(badge.detail)"
        }.joined(separator: "\n")

        addSection(header: String(localized: "Latest Updates"), text: text)
    }

    private func addPlatformReleaseDates(_ dates: [PlatformReleaseDate]) {
        let groups = groupedReleaseDates(dates)
        let text = groups.prefix(8).map { group in
            var labelParts = [group.displayDate]

            if group.regionName != String(localized: "Worldwide") {
                labelParts.append(group.regionName)
            }
            if let status = group.status, !status.isEmpty {
                labelParts.append(status)
            }
            if group.accuracy != .exact {
                labelParts.append(group.accuracy.title)
            }

            let platforms = group.platforms.sorted().joined(separator: ", ")
            return "• \(labelParts.joined(separator: " · ")): \(platforms)"
        }.joined(separator: "\n")

        addSection(header: String(localized: "Platform Release Dates"), text: text)
    }

    private struct ReleaseDateGroup {
        let displayDate: String
        let regionName: String
        let status: String?
        let accuracy: ReleaseAccuracy
        let timestamp: Date?
        var platforms: Set<String>
    }

    private func groupedReleaseDates(_ dates: [PlatformReleaseDate]) -> [ReleaseDateGroup] {
        var groups: [String: ReleaseDateGroup] = [:]

        for date in dates {
            let key = [
                date.displayDate,
                date.regionName,
                date.status ?? "",
                date.accuracy.rawValue
            ].joined(separator: "|")

            if var group = groups[key] {
                group.platforms.insert(date.platformName)
                groups[key] = group
            } else {
                groups[key] = ReleaseDateGroup(
                    displayDate: date.displayDate,
                    regionName: date.regionName,
                    status: date.status,
                    accuracy: date.accuracy,
                    timestamp: date.timestamp,
                    platforms: [date.platformName]
                )
            }
        }

        return groups.values.sorted {
            ($0.timestamp ?? .distantFuture) < ($1.timestamp ?? .distantFuture)
        }
    }

    // MARK: - Похожие игры

    private func addSimilarGames(_ games: [GamesStorage]) {
        similarGames = games

        let headerLabel = UILabel()
        headerLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        headerLabel.text = String(localized: "Similar Games")
        addPadded(headerLabel)
        contentStack.setCustomSpacing(8, after: headerLabel)

        let cardsStack = UIStackView()
        cardsStack.axis = .horizontal
        cardsStack.alignment = .top
        cardsStack.spacing = 12
        cardsStack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        cardsStack.isLayoutMarginsRelativeArrangement = true

        for (index, game) in games.enumerated() {
            cardsStack.addArrangedSubview(makeSimilarGameCard(for: game, index: index))
        }

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        cardsStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(cardsStack)

        NSLayoutConstraint.activate([
            cardsStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            cardsStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            cardsStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            cardsStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            scrollView.heightAnchor.constraint(equalTo: cardsStack.heightAnchor)
        ])

        addArranged(scrollView)
    }

    private func makeSimilarGameCard(for game: GamesStorage, index: Int) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = .secondarySystemFill
        imageView.widthAnchor.constraint(equalToConstant: 200).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 112).isActive = true
        loadPoster(for: game, into: imageView)

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.numberOfLines = 2
        titleLabel.text = game.gameTitle

        let card = UIStackView(arrangedSubviews: [imageView, titleLabel])
        card.axis = .vertical
        card.spacing = 6
        card.widthAnchor.constraint(equalToConstant: 200).isActive = true

        card.tag = index
        card.isUserInteractionEnabled = true
        card.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(similarGameTapped(_:)))
        )

        return card
    }

    @objc private func similarGameTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag, similarGames.indices.contains(index) else { return }

        let detailViewController = GameDetailViewController(game: similarGames[index], gameService: gameService)
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func addRating(_ details: GameDetails) {
        let ratingLabel = UILabel()

        if details.ratingsCount > 0 {
            let text = NSMutableAttributedString(
                string: "★ \(String(format: "%.1f", details.rating))",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: UIColor.systemOrange
                ]
            )
            text.append(NSAttributedString(
                string: "  ·  \(ratingsCountText(details.ratingsCount))",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            ))
            ratingLabel.attributedText = text
        } else {
            ratingLabel.font = .systemFont(ofSize: 15)
            ratingLabel.textColor = .secondaryLabel
            ratingLabel.text = String(localized: "No ratings yet")
        }

        addPadded(ratingLabel)
    }

    private func ratingsCountText(_ count: Int) -> String {
        // Формы множественного числа берутся из каталога строк (Localizable.xcstrings).
        String(localized: "\(count) ratings")
    }

    private func showDetailsLoading() {
        clearDetails()
        spinner.startAnimating()
        detailsStack.addArrangedSubview(spinner)
    }

    private func showError(_ error: Error) {
        clearDetails()

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = String(localized: "Couldn't load details")

        let detailLabel = UILabel()
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .tertiaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.text = error.localizedDescription

        var config = UIButton.Configuration.borderedProminent()
        config.title = String(localized: "Retry")
        let retryButton = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.loadDetails()
        })

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true

        detailsStack.addArrangedSubview(stack)
    }

    private func clearDetails() {
        spinner.stopAnimating()
        detailsStack.arrangedSubviews.forEach { view in
            detailsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    // MARK: - Секции

    private func addSection(header: String, text: String) {
        let headerLabel = UILabel()
        headerLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        headerLabel.text = header
        addPadded(headerLabel)

        let textLabel = UILabel()
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .label
        textLabel.numberOfLines = 0
        textLabel.text = text
        addPadded(textLabel)

        contentStack.setCustomSpacing(8, after: headerLabel)
    }

    private func addScreenshots(_ urls: [URL]) {
        let headerLabel = UILabel()
        headerLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        headerLabel.text = String(localized: "Screenshots")
        addPadded(headerLabel)
        contentStack.setCustomSpacing(8, after: headerLabel)

        let screenshotsStack = UIStackView()
        screenshotsStack.axis = .horizontal
        screenshotsStack.spacing = 12
        screenshotsStack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        screenshotsStack.isLayoutMarginsRelativeArrangement = true

        screenshotURLs = urls

        for (index, url) in urls.enumerated() {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 12
            imageView.backgroundColor = .secondarySystemFill
            imageView.widthAnchor.constraint(equalToConstant: 280).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 158).isActive = true

            imageView.tag = index
            imageView.isUserInteractionEnabled = true
            imageView.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(screenshotTapped(_:)))
            )

            screenshotsStack.addArrangedSubview(imageView)
            loadImage(from: url, into: imageView)
        }

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        screenshotsStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(screenshotsStack)

        NSLayoutConstraint.activate([
            screenshotsStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            screenshotsStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            screenshotsStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            screenshotsStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            scrollView.heightAnchor.constraint(equalTo: screenshotsStack.heightAnchor)
        ])

        addArranged(scrollView)
    }

    @objc private func screenshotTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag, screenshotURLs.indices.contains(index) else { return }

        let viewer = ScreenshotViewerController(urls: screenshotURLs, startIndex: index)
        present(viewer, animated: true)
    }

    // MARK: - Вспомогательные

    /// Оборачивает вью в контейнер с горизонтальными отступами по 16pt.
    private func addPadded(_ subview: UIView) {
        let container = UIView()
        subview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subview)

        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: container.topAnchor),
            subview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            subview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            subview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
        ])

        if isBuildingDetails {
            detailsStack.addArrangedSubview(container)
        } else {
            contentStack.addArrangedSubview(container)
        }
    }

    private func addArranged(_ subview: UIView) {
        if isBuildingDetails {
            detailsStack.addArrangedSubview(subview)
        } else {
            contentStack.addArrangedSubview(subview)
        }
    }

    /// Постер с выбором лучшего арта и запасными вариантами.
    private func loadPoster(for game: GamesStorage, into imageView: UIImageView) {
        Task { [weak imageView] in
            guard let image = await ImageCache.shared.loadPoster(for: game) else { return }
            imageView?.image = image
        }
    }

    private func loadImage(from url: URL?, into imageView: UIImageView) {
        guard let url else { return }

        if let cached = ImageCache.shared.image(for: url) {
            imageView.image = cached
            return
        }

        Task { [weak imageView] in
            guard let image = await ImageCache.shared.loadImage(from: url) else { return }
            imageView?.image = image
        }
    }

}

// MARK: - Stretchy-обложка

extension GameDetailViewController: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // При оттягивании списка вниз обложка растягивается с лёгким параллаксом.
        let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        if offset < 0 {
            let scale = 1 - offset / 300
            coverImageView.transform = CGAffineTransform(translationX: 0, y: offset / 2)
                .scaledBy(x: scale, y: scale)
        } else {
            coverImageView.transform = .identity
        }
    }

}
