
import UIKit

/// Все игры франшизы, новые сверху.
class FranchiseViewController: UITableViewController {

    private let franchise: GameFranchise
    private let gameService: GameCatalogService
    private var games: [GamesStorage] = []
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(franchise: GameFranchise, gameService: GameCatalogService) {
        self.franchise = franchise
        self.gameService = gameService
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = franchise.name
        tableView.rowHeight = 112
        tableView.register(UINib(nibName: "GameCell", bundle: nil), forCellReuseIdentifier: "GameCell")

        spinner.startAnimating()
        tableView.backgroundView = spinner

        load()
    }

    private func load() {
        let franchiseID = franchise.id
        let gameService = gameService

        Task { [weak self] in
            let games = (try? await gameService.fetchFranchiseGames(franchiseID: franchiseID)) ?? []
            guard let self else { return }
            self.games = games
            spinner.stopAnimating()
            tableView.backgroundView = nil
            tableView.reloadData()
        }
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
