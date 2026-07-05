
import UIKit

class TableViewController: UITableViewController {

    private var games: [GamesStorage] = []
    private let rawgService = RawgService()

    private var currentPage = 1
    private var hasMorePages = true
    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Upcoming Games"
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.rowHeight = 112

        let cellTypeNib = UINib(nibName: "GameCell", bundle: nil)
        tableView.register(cellTypeNib, forCellReuseIdentifier: "GameCell")

        loadNextPage()
    }

    private func loadNextPage() {
        guard hasMorePages, !isLoading else { return }
        isLoading = true

        Task {
            do {
                let (fetched, hasMore) = try await rawgService.fetchGames(page: currentPage)

                games.append(contentsOf: fetched)
                hasMorePages = hasMore
                currentPage += 1
                tableView.reloadData()
            } catch {
                print("RAWG loading error:", error)
            }

            isLoading = false
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

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Подгружаем следующую страницу, когда пользователь долистал почти до конца.
        if indexPath.row >= games.count - 5 {
            loadNextPage()
        }
    }

}
