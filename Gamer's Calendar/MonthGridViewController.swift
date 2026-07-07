
import UIKit

/// Календарная сетка месяца: на днях с релизами — постеры игр.
/// Тап по дню открывает шторку со списком релизов этого дня.
class MonthGridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {

    private let gameService = IGDBService()
    private let calendar = Calendar.current

    /// Первое число отображаемого месяца.
    private var month: Date {
        didSet { reload() }
    }

    /// Игры месяца, сгруппированные по числу месяца.
    private var gamesByDay: [Int: [GamesStorage]] = [:]

    /// Кэш уже загруженных месяцев: листание назад-вперёд мгновенное.
    private var monthCache: [Date: [Int: [GamesStorage]]] = [:]

    /// Клетки сетки; nil — пустые клетки до первого числа месяца.
    private var days: [Int?] = []

    private let monthLabel = UILabel()
    private var collectionView: UICollectionView!
    private var loadTask: Task<Void, Never>?

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

    init() {
        month = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = String(localized: "Calendar")

        setupLayout()
        reload()
    }

    // MARK: - Вёрстка

    private func setupLayout() {
        let previousButton = UIButton(type: .system)
        previousButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        previousButton.addAction(UIAction { [weak self] _ in self?.shiftMonth(by: -1) }, for: .touchUpInside)

        let nextButton = UIButton(type: .system)
        nextButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        nextButton.addAction(UIAction { [weak self] _ in self?.shiftMonth(by: 1) }, for: .touchUpInside)

        monthLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        monthLabel.textAlignment = .center

        // Стрелки прижаты к названию месяца, вся группа центрируется.
        let headerContent = UIStackView(arrangedSubviews: [previousButton, monthLabel, nextButton])
        headerContent.axis = .horizontal
        headerContent.spacing = 20

        let header = UIView()
        headerContent.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerContent)
        NSLayoutConstraint.activate([
            headerContent.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            headerContent.topAnchor.constraint(equalTo: header.topAnchor),
            headerContent.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])

        // Строка дней недели с учётом первого дня недели в локали.
        var symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        symbols = Array(symbols[shift...] + symbols[..<shift])

        let weekdayRow = UIStackView(arrangedSubviews: symbols.map { symbol in
            let label = UILabel()
            label.text = symbol.uppercased()
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            return label
        })
        weekdayRow.distribution = .fillEqually

        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1.0 / 7.0),
                heightDimension: .fractionalHeight(1)
            ))
            item.contentInsets = NSDirectionalEdgeInsets(top: 1.5, leading: 1.5, bottom: 1.5, trailing: 1.5)

            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .fractionalWidth(1.0 / 7.0 * 1.45)
                ),
                subitems: [item]
            )
            return NSCollectionLayoutSection(group: group)
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(DayCell.self, forCellWithReuseIdentifier: "DayCell")

        let stack = UIStackView(arrangedSubviews: [header, weekdayRow, collectionView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(4, after: weekdayRow)

        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - Данные

    private func shiftMonth(by delta: Int) {
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func reload() {
        loadTask?.cancel()

        let raw = monthFormatter.string(from: month)
        monthLabel.text = raw.prefix(1).uppercased() + raw.dropFirst()

        rebuildDays()

        if let cached = monthCache[month] {
            gamesByDay = cached
            collectionView.reloadData()
            prefetchAdjacentMonths()
            return
        }

        gamesByDay = [:]
        collectionView.reloadData()

        loadTask = Task {
            guard let byDay = await loadMonth(month), !Task.isCancelled else { return }
            gamesByDay = byDay
            collectionView.reloadData()
            prefetchAdjacentMonths()
        }
    }

    /// Загружает месяц и раскладывает игры по дням.
    /// Внутри дня — по популярности: постером клетки становится самая ожидаемая.
    private func loadMonth(_ month: Date) async -> [Int: [GamesStorage]]? {
        if let cached = monthCache[month] {
            return cached
        }

        guard let interval = calendar.dateInterval(of: .month, for: month),
              let games = try? await gameService.fetchGames(from: interval.start, to: interval.end) else {
            return nil
        }

        var byDay: [Int: [GamesStorage]] = [:]
        for game in games {
            guard let date = game.releaseDate else { continue }
            byDay[calendar.component(.day, from: date), default: []].append(game)
        }

        let sorted = byDay.mapValues { dayGames in
            dayGames.sorted { ($0.hypes ?? 0) > ($1.hypes ?? 0) }
        }
        monthCache[month] = sorted
        return sorted
    }

    /// Фоном загружает соседние месяцы вместе с постерами клеток,
    /// чтобы листание стрелками было без видимой прогрузки.
    private func prefetchAdjacentMonths() {
        for delta in [1, -1] {
            guard let neighbor = calendar.date(byAdding: .month, value: delta, to: month) else { continue }

            Task {
                guard let byDay = await loadMonth(neighbor) else { return }
                for games in byDay.values {
                    guard let candidates = games.first?.portraitPosterCandidates else { continue }
                    _ = await ImageCache.shared.loadImage(fromCandidates: candidates)
                }
            }
        }
    }

    private func rebuildDays() {
        guard let range = calendar.range(of: .day, in: .month, for: month) else {
            days = []
            return
        }
        let firstWeekday = calendar.component(.weekday, from: month)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
        days = Array(repeating: nil, count: leadingEmpty) + range.map { $0 }
    }

    // MARK: - UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        days.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "DayCell", for: indexPath) as! DayCell
        let day = days[indexPath.item]
        cell.configure(
            day: day,
            games: day.flatMap { gamesByDay[$0] } ?? [],
            isToday: day.map(isToday) ?? false
        )
        return cell
    }

    private func isToday(_ day: Int) -> Bool {
        calendar.isDate(.now, equalTo: month, toGranularity: .month)
            && calendar.component(.day, from: .now) == day
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let day = days[indexPath.item],
              let games = gamesByDay[day], !games.isEmpty else { return }

        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = day
        let date = calendar.date(from: components) ?? month

        let dayController = DayGamesViewController(date: date, games: games, gameService: gameService)
        let navigation = UINavigationController(rootViewController: dayController)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }

}

// MARK: - Шторка с релизами дня

/// Список игр, выходящих в выбранный день календаря.
class DayGamesViewController: UITableViewController {

    private let games: [GamesStorage]
    private let gameService: IGDBService

    init(date: Date, games: [GamesStorage], gameService: IGDBService) {
        self.games = games
        self.gameService = gameService
        super.init(style: .plain)
        navigationItem.title = date.formatted(date: .long, time: .omitted)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = 112
        tableView.register(UINib(nibName: "GameCell", bundle: nil), forCellReuseIdentifier: "GameCell")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        games.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "GameCell", for: indexPath) as! GameCell
        cell.configure(with: games[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let detailViewController = GameDetailViewController(game: games[indexPath.row], gameService: gameService)
        navigationController?.pushViewController(detailViewController, animated: true)
    }

}

// MARK: - Клетка дня

/// Клетка календаря: число месяца и постер первой игры дня.
private class DayCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let dimView = UIView()
    private let dayLabel = UILabel()
    private let countLabel = UILabel()

    /// Токен от подстановки чужой картинки в переиспользованную клетку.
    private var currentImageURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimView.frame = contentView.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(dimView)

        dayLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dayLabel)

        countLabel.font = .systemFont(ofSize: 10, weight: .bold)
        countLabel.textColor = .white
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            dayLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            dayLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            countLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(day: Int?, games: [GamesStorage], isToday: Bool) {
        guard let day else {
            dayLabel.text = nil
            countLabel.text = nil
            imageView.image = nil
            currentImageURL = nil
            dimView.isHidden = true
            contentView.backgroundColor = .clear
            contentView.layer.borderWidth = 0
            return
        }

        dayLabel.text = String(day)
        countLabel.text = games.count > 1 ? "+\(games.count - 1)" : nil
        contentView.backgroundColor = .secondarySystemFill

        contentView.layer.borderWidth = isToday ? 2 : 0
        contentView.layer.borderColor = UIColor.systemPurple.cgColor

        // Вертикальная обложка лучше вписывается в клетку календаря.
        let candidates = games.first?.portraitPosterCandidates ?? []
        dimView.isHidden = candidates.isEmpty
        dayLabel.textColor = candidates.isEmpty ? .label : .white
        loadImage(candidates: candidates)
    }

    private func loadImage(candidates: [URL]) {
        let requestKey = candidates.first
        currentImageURL = requestKey
        imageView.image = nil

        guard requestKey != nil else { return }

        for url in candidates {
            if let cached = ImageCache.shared.image(for: url) {
                imageView.image = cached
                return
            }
        }

        Task {
            guard let image = await ImageCache.shared.loadImage(fromCandidates: candidates) else { return }
            guard currentImageURL == requestKey else { return }
            imageView.image = image
        }
    }

}
