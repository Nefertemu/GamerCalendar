
import UIKit

class TableViewController: UITableViewController {

    private var sections: [MonthSection] = []
    private let gameService: GameCatalogService

    private var currentPage = 1
    private var hasMorePages = true
    private var isLoading = false

    /// Растёт при каждом сбросе списка; ответы устаревших запросов отбрасываются.
    private var loadGeneration = 0

    /// Диапазоны «показывать игры на …» в месяцах.
    private let windowOptions = [3, 6, 12, 24, 36, 60]

    /// Выбранный диапазон; переживает перезапуск приложения.
    private var monthsAhead = UserDefaults.standard.object(forKey: "filter.monthsAhead") as? Int ?? 36 {
        didSet {
            UserDefaults.standard.set(monthsAhead, forKey: "filter.monthsAhead")
            reloadFromScratch()
        }
    }

    /// Выбранная платформа; переживает перезапуск приложения.
    private var platformFilter = PlatformFamily(rawValue: UserDefaults.standard.string(forKey: "filter.platform") ?? "") {
        didSet {
            UserDefaults.standard.set(platformFilter?.rawValue, forKey: "filter.platform")
            reloadFromScratch()
        }
    }

    /// Выбранный жанр; переживает перезапуск приложения.
    private var genreFilter = (UserDefaults.standard.object(forKey: "filter.genre") as? Int).flatMap(GenreFilter.init(rawValue:)) {
        didSet {
            UserDefaults.standard.set(genreFilter?.rawValue, forKey: "filter.genre")
            reloadFromScratch()
        }
    }

    private enum SortOrder {
        case releaseDate
        case hype
    }

    private var sortOrder: SortOrder = .releaseDate {
        didSet { reloadFromScratch() }
    }

    private var searchQuery: String? {
        didSet { reloadFromScratch() }
    }
    private var searchDebounceTask: Task<Void, Never>?

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

    init(style: UITableView.Style, gameService: GameCatalogService = IGDBService()) {
        self.gameService = gameService
        super.init(style: style)
    }

    required init?(coder: NSCoder) {
        self.gameService = IGDBService()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Меняем только заголовок навбара: self.title перетёр бы подпись таба.
        navigationItem.title = String(localized: "Upcoming Games")
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.rowHeight = 112
        tableView.backgroundColor = .systemBackground

        let cellTypeNib = UINib(nibName: "GameCell", bundle: nil)
        tableView.register(cellTypeNib, forCellReuseIdentifier: "GameCell")

        setupSearch()
        setupRefreshControl()
        updateMenus()

        // Показываем прошлую первую страницу мгновенно, пока грузится свежая.
        let cached = FirstPageCache.load()
        if !cached.isEmpty {
            append(cached)
            tableView.reloadData()
        }

        loadNextPage()
    }

    // MARK: - Поиск

    private func setupSearch() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Search games")
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
    }

    // MARK: - Pull-to-refresh

    private func setupRefreshControl() {
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
    }

    @objc private func refreshPulled() {
        reloadFromScratch()
    }

    // MARK: - Меню диапазона и платформ

    private func updateMenus() {
        let windowActions = windowOptions.map { months in
            UIAction(
                title: windowTitle(forMonths: months),
                state: months == monthsAhead ? .on : .off
            ) { [weak self] _ in
                self?.monthsAhead = months
            }
        }

        let sortActions = [
            UIAction(
                title: String(localized: "By release date"),
                state: sortOrder == .releaseDate ? .on : .off
            ) { [weak self] _ in
                self?.sortOrder = .releaseDate
            },
            UIAction(
                title: String(localized: "Most anticipated"),
                image: UIImage(systemName: "flame"),
                state: sortOrder == .hype ? .on : .off
            ) { [weak self] _ in
                self?.sortOrder = .hype
            }
        ]

        let calendarButton = UIBarButtonItem(
            image: UIImage(systemName: "calendar"),
            menu: UIMenu(children: [
                UIMenu(options: .displayInline, children: sortActions),
                UIMenu(title: String(localized: "Show games for"), options: .displayInline, children: windowActions)
            ])
        )

        let allPlatformsAction = UIAction(
            title: String(localized: "All Platforms"),
            state: platformFilter == nil ? .on : .off
        ) { [weak self] _ in
            self?.platformFilter = nil
        }
        let platformActions = [allPlatformsAction] + PlatformFamily.allCases.map { platform in
            UIAction(
                title: platform.title,
                state: platform == platformFilter ? .on : .off
            ) { [weak self] _ in
                self?.platformFilter = platform
            }
        }

        let allGenresAction = UIAction(
            title: String(localized: "All Genres"),
            state: genreFilter == nil ? .on : .off
        ) { [weak self] _ in
            self?.genreFilter = nil
        }
        let genreActions = [allGenresAction] + GenreFilter.allCases.map { genre in
            UIAction(
                title: genre.title,
                state: genre == genreFilter ? .on : .off
            ) { [weak self] _ in
                self?.genreFilter = genre
            }
        }

        let filterIcon = platformFilter == nil && genreFilter == nil
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
        let filterButton = UIBarButtonItem(
            image: UIImage(systemName: filterIcon),
            menu: UIMenu(children: [
                UIMenu(title: String(localized: "Platform"), options: .displayInline, children: platformActions),
                UIMenu(title: String(localized: "Genre"), options: .displayInline, children: genreActions)
            ])
        )

        navigationItem.rightBarButtonItems = [calendarButton, filterButton]
    }

    private func windowTitle(forMonths months: Int) -> String {
        // Формы множественного числа берутся из каталога строк (Localizable.xcstrings).
        if months < 12 {
            return String(localized: "\(months) months")
        }
        return String(localized: "\(months / 12) years")
    }

    // MARK: - Загрузка

    private func reloadFromScratch() {
        loadGeneration += 1
        sections = []
        currentPage = 1
        hasMorePages = true
        isLoading = false
        tableView.backgroundView = nil
        tableView.reloadData()
        updateMenus()
        updateNavigationTitle()
        loadNextPage()
    }

    private func loadNextPage() {
        guard hasMorePages, !isLoading else { return }
        isLoading = true

        let generation = loadGeneration
        let page = currentPage
        let monthsAhead = monthsAhead
        let searchQuery = searchQuery
        let platformFilter = platformFilter
        let genreFilter = genreFilter
        let sortByHype = sortOrder == .hype
        let shouldCacheFirstPage = page == 1
            && searchQuery == nil
            && platformFilter == nil
            && genreFilter == nil
            && !sortByHype
        let gameService = gameService

        Task { [weak self] in
            do {
                let (fetched, hasMore) = try await gameService.fetchGames(
                    page: page,
                    monthsAhead: monthsAhead,
                    search: searchQuery,
                    platform: platformFilter,
                    genre: genreFilter,
                    sortByHype: sortByHype
                )

                guard let self else { return }
                // Пока грузилась страница, пользователь мог сменить фильтры —
                // тогда этот ответ уже устарел и его нельзя добавлять в список.
                guard generation == loadGeneration else { return }

                if page == 1 {
                    // Первая страница из сети заменяет кэшированную с запуска.
                    sections = []

                    if shouldCacheFirstPage {
                        FirstPageCache.save(fetched)
                    }
                }

                append(fetched)
                hasMorePages = hasMore
                currentPage += 1
                isLoading = false
                tableView.reloadData()
                showEmptyStateIfNeeded()
            } catch {
                guard let self else { return }
                guard generation == loadGeneration else { return }
                isLoading = false
                if sections.isEmpty {
                    showErrorState(error: error)
                }
            }

            self?.refreshControl?.endRefreshing()
        }
    }

    /// Раскладывает игры по секциям-месяцам. Игры приходят по возрастанию
    /// даты релиза, поэтому новый месяц всегда добавляется в конец.
    private func append(_ games: [GamesStorage]) {
        // При сортировке по хайпу месяцы идут вразнобой — список плоский, без секций.
        guard sortOrder == .releaseDate else {
            if sections.isEmpty {
                sections = [MonthSection(month: .distantPast, games: games)]
            } else {
                sections[0].games.append(contentsOf: games)
            }
            return
        }

        MonthGrouper.append(games, to: &sections)
    }

    // MARK: - Пустое состояние и ошибки

    private func showEmptyStateIfNeeded() {
        guard sections.isEmpty, !hasMorePages else { return }

        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.text = String(localized: "No games found")
        tableView.backgroundView = label
    }

    private func showErrorState(error: Error) {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = String(localized: "Couldn't load games")

        let detailLabel = UILabel()
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .tertiaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.text = error.localizedDescription

        var buttonConfig = UIButton.Configuration.borderedProminent()
        buttonConfig.title = String(localized: "Retry")
        let retryButton = UIButton(configuration: buttonConfig, primaryAction: UIAction { [weak self] _ in
            self?.reloadFromScratch()
        })

        let stack = UIStackView(arrangedSubviews: [label, detailLabel, retryButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center

        let container = UIView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32)
        ])

        tableView.backgroundView = container
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].games.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard sortOrder == .releaseDate else { return nil }
        return monthTitle(for: sections[section].month)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "GameCell", for: indexPath) as! GameCell
        cell.configure(with: sections[indexPath.section].games[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let game = sections[indexPath.section].games[indexPath.row]
        let detailViewController = GameDetailViewController(game: game, gameService: gameService)
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Подгружаем следующую страницу, когда пользователь долистал почти до конца.
        guard indexPath.section == sections.count - 1 else { return }
        if indexPath.row >= sections[indexPath.section].games.count - 5 {
            loadNextPage()
        }
    }

    // MARK: - Заголовок с текущим месяцем

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationTitle()
    }

    /// В самом верху списка — название экрана, при пролистывании
    /// заголовок показывает месяц верхней видимой игры.
    private func updateNavigationTitle() {
        let topOffset = tableView.contentOffset.y + tableView.adjustedContentInset.top

        if topOffset <= 8 || sections.isEmpty {
            navigationItem.title = String(localized: "Upcoming Games")
        } else if sortOrder == .hype {
            navigationItem.title = String(localized: "Most anticipated")
        } else if let topRow = tableView.indexPathsForVisibleRows?.first {
            navigationItem.title = monthTitle(for: sections[topRow.section].month)
        }
    }

    private func monthTitle(for month: Date) -> String {
        // Заглавная только первая буква: .capitalized сделал бы «Июль 2026 Г.»
        let raw = monthFormatter.string(from: month)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

}

// MARK: - UISearchResultsUpdating

extension TableViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let newQuery = text.isEmpty ? nil : text
        guard newQuery != searchQuery else { return }

        // Небольшая задержка, чтобы не дёргать API на каждую введённую букву.
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            searchQuery = newQuery
        }
    }

}
