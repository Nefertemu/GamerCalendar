
import UIKit

class TableViewController: UITableViewController {

    private var games: [GamesStorage] = []
    private let rawgService = RawgService()

    private var currentPage = 1
    private var hasMorePages = true
    private var isLoading = false

    private let yearOptions = [1, 2, 3, 5]
    private var yearsAhead = 3 {
        didSet { reloadFromScratch() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Upcoming Games"
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.rowHeight = 112

        let cellTypeNib = UINib(nibName: "GameCell", bundle: nil)
        tableView.register(cellTypeNib, forCellReuseIdentifier: "GameCell")

        updateYearsMenu()
        loadNextPage()
    }

    // MARK: - Выбор диапазона

    private func updateYearsMenu() {
        let actions = yearOptions.map { years in
            UIAction(
                title: yearsTitle(for: years),
                state: years == yearsAhead ? .on : .off
            ) { [weak self] _ in
                self?.yearsAhead = years
            }
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "calendar"),
            menu: UIMenu(title: "Показывать игры на", children: actions)
        )
    }

    private func yearsTitle(for years: Int) -> String {
        switch years {
        case 1: return "1 год"
        case 2, 3, 4: return "\(years) года"
        default: return "\(years) лет"
        }
    }

    private func reloadFromScratch() {
        games = []
        currentPage = 1
        hasMorePages = true
        isLoading = false
        tableView.reloadData()
        updateYearsMenu()
        loadNextPage()
    }

    private func loadNextPage() {
        guard hasMorePages, !isLoading else { return }
        isLoading = true

        let requestedYears = yearsAhead

        Task {
            do {
                let (fetched, hasMore) = try await rawgService.fetchGames(page: currentPage, yearsAhead: requestedYears)

                // Пока грузилась страница, пользователь мог сменить диапазон —
                // тогда этот ответ уже устарел и его нельзя добавлять в список.
                guard requestedYears == yearsAhead else { return }

                games.append(contentsOf: fetched)
                hasMorePages = hasMore
                currentPage += 1
                tableView.reloadData()
            } catch {
                print("RAWG loading error:", error)
            }

            if requestedYears == yearsAhead {
                isLoading = false
            }
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
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

        let detailViewController = GameDetailViewController(game: games[indexPath.row], rawgService: rawgService)
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Подгружаем следующую страницу, когда пользователь долистал почти до конца.
        if indexPath.row >= games.count - 5 {
            loadNextPage()
        }
    }

}
