
import UIKit

class TableViewController: UITableViewController {

    /// Игры, сгруппированные по месяцу релиза.
    private struct MonthSection {
        let month: Date
        var games: [GamesStorage]
    }

    private var sections: [MonthSection] = []
    private let gameService = IGDBService()

    private var currentPage = 1
    private var hasMorePages = true
    private var isLoading = false

    /// Растёт при каждом сбросе списка; ответы устаревших запросов отбрасываются.
    private var loadGeneration = 0

    private let yearOptions = [1, 2, 3, 5]
    private var yearsAhead = 3 {
        didSet { reloadFromScratch() }
    }

    private var platformFilter: PlatformFamily? {
        didSet { reloadFromScratch() }
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

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: "Upcoming Games")
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.rowHeight = 112

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
        let yearActions = yearOptions.map { years in
            UIAction(
                title: yearsTitle(for: years),
                state: years == yearsAhead ? .on : .off
            ) { [weak self] _ in
                self?.yearsAhead = years
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
                UIMenu(title: String(localized: "Show games for"), options: .displayInline, children: yearActions)
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

        let filterIcon = platformFilter == nil
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
        let filterButton = UIBarButtonItem(
            image: UIImage(systemName: filterIcon),
            menu: UIMenu(title: String(localized: "Platform"), children: platformActions)
        )

        navigationItem.rightBarButtonItems = [calendarButton, filterButton]
    }

    private func yearsTitle(for years: Int) -> String {
        // Формы множественного числа берутся из каталога строк (Localizable.xcstrings).
        String(localized: "\(years) years")
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

        Task {
            do {
                let (fetched, hasMore) = try await gameService.fetchGames(
                    page: currentPage,
                    yearsAhead: yearsAhead,
                    search: searchQuery,
                    platform: platformFilter,
                    sortByHype: sortOrder == .hype
                )

                // Пока грузилась страница, пользователь мог сменить фильтры —
                // тогда этот ответ уже устарел и его нельзя добавлять в список.
                guard generation == loadGeneration else { return }

                if currentPage == 1 {
                    // Первая страница из сети заменяет кэшированную с запуска.
                    sections = []

                    if searchQuery == nil, platformFilter == nil, sortOrder == .releaseDate {
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
                guard generation == loadGeneration else { return }
                isLoading = false
                if sections.isEmpty {
                    showErrorState()
                }
            }

            refreshControl?.endRefreshing()
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

        let calendar = Calendar.current
        for game in games {
            guard let date = game.releaseDate else { continue }

            if let lastIndex = sections.indices.last,
               calendar.isDate(sections[lastIndex].month, equalTo: date, toGranularity: .month) {
                sections[lastIndex].games.append(game)
            } else {
                let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
                sections.append(MonthSection(month: month, games: [game]))
            }
        }
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

    private func showErrorState() {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.text = String(localized: "Couldn't load games")

        var buttonConfig = UIButton.Configuration.borderedProminent()
        buttonConfig.title = String(localized: "Retry")
        let retryButton = UIButton(configuration: buttonConfig, primaryAction: UIAction { [weak self] _ in
            self?.reloadFromScratch()
        })

        let stack = UIStackView(arrangedSubviews: [label, retryButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center

        let container = UIView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
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
        return monthFormatter.string(from: sections[section].month).capitalized
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
            title = String(localized: "Upcoming Games")
        } else if sortOrder == .hype {
            title = String(localized: "Most anticipated")
        } else if let topRow = tableView.indexPathsForVisibleRows?.first {
            title = monthFormatter.string(from: sections[topRow.section].month).capitalized
        }
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
