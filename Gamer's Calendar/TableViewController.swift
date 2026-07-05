
import UIKit

class TableViewController: UITableViewController {

    private var games: [GamesStorage] = []
    private let rawgService = RawgService()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Upcoming Games"
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.rowHeight = 112

        let cellTypeNib = UINib(nibName: "GameCell", bundle: nil)
        tableView.register(cellTypeNib, forCellReuseIdentifier: "GameCell")

        loadGames()
    }

    private func loadGames() {
        Task {
            do {
                var fetched = try await rawgService.fetchGames()
                fetched.sort { ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture) }

                games = fetched
                tableView.reloadData()
            } catch {
                print("RAWG loading error:", error)
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

}
