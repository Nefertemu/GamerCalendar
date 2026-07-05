
import UIKit

/// Экран с подробной информацией об игре: обложка, описание,
/// жанры, разработчики и скриншоты.
class GameDetailViewController: UIViewController {

    private let game: GamesStorage
    private let rawgService: RawgService

    private let contentStack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var screenshotURLs: [URL] = []

    init(game: GamesStorage, rawgService: RawgService) {
        self.game = game
        self.rawgService = rawgService
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
    }

    // MARK: - Layout

    private func setupLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    // MARK: - Базовая информация (доступна сразу из списка)

    private func showBasicInfo() {
        let coverImageView = UIImageView()
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.backgroundColor = .secondarySystemFill
        coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor, multiplier: 9.0 / 16.0).isActive = true
        contentStack.addArrangedSubview(coverImageView)
        loadImage(from: game.imageURL, into: coverImageView)

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.text = game.gameTitle
        addPadded(titleLabel)

        let releaseLabel = UILabel()
        releaseLabel.font = .systemFont(ofSize: 15)
        releaseLabel.textColor = .secondaryLabel
        let dateText = game.releaseDate?.formatted(date: .long, time: .omitted) ?? "Unknown date"
        releaseLabel.text = "Дата выхода: \(dateText)"
        addPadded(releaseLabel)

        if !game.platforms.isEmpty {
            addSection(header: "Платформы", text: game.platforms)
        }

        spinner.startAnimating()
        contentStack.addArrangedSubview(spinner)
    }

    // MARK: - Детали из API

    private func loadDetails() {
        Task {
            do {
                let details = try await rawgService.fetchGameDetails(id: game.id)
                spinner.removeFromSuperview()
                showDetails(details)
            } catch {
                spinner.removeFromSuperview()
                showError()
                print("RAWG details loading error:", error)
            }
        }
    }

    private func showDetails(_ details: GameDetails) {
        addRating(details)

        if !details.about.isEmpty {
            addSection(header: "Об игре", text: details.about)
        }

        if !details.genres.isEmpty {
            addSection(header: "Жанры", text: details.genres)
        }

        if !details.developers.isEmpty {
            addSection(header: "Разработчики", text: details.developers)
        }

        if !details.screenshots.isEmpty {
            addScreenshots(details.screenshots)
        }
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
            ratingLabel.text = "Пока нет оценок"
        }

        addPadded(ratingLabel)
    }

    private func ratingsCountText(_ count: Int) -> String {
        let word: String
        switch (count % 100, count % 10) {
        case (11...14, _): word = "оценок"
        case (_, 1): word = "оценка"
        case (_, 2...4): word = "оценки"
        default: word = "оценок"
        }
        return "\(count) \(word)"
    }

    private func showError() {
        let errorLabel = UILabel()
        errorLabel.font = .systemFont(ofSize: 15)
        errorLabel.textColor = .secondaryLabel
        errorLabel.textAlignment = .center
        errorLabel.text = "Не удалось загрузить подробности"
        addPadded(errorLabel)
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
        headerLabel.text = "Скриншоты"
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

        contentStack.addArrangedSubview(scrollView)
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

        contentStack.addArrangedSubview(container)
    }

    private func loadImage(from url: URL?, into imageView: UIImageView) {
        guard let url else { return }

        if let cached = ImageCache.shared.image(for: url) {
            imageView.image = cached
            return
        }

        Task {
            guard let image = await ImageCache.shared.loadImage(from: url) else { return }
            imageView.image = image
        }
    }

}
