
import UIKit

/// Вкладка «Жду»: отслеживаемые игры с обратным отсчётом до релиза.
/// Список хранится локально, сеть нужна только для картинок.
class WatchlistViewController: UITableViewController {

    private var games: [GamesStorage] = []
    private let gameService = IGDBService()

    /// Игры, у которых при последней сверке с IGDB изменилась дата релиза.
    private var changedGameIDs: Set<Int> = []

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: "Watchlist")
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.rowHeight = 112

        let cellTypeNib = UINib(nibName: "GameCell", bundle: nil)
        tableView.register(cellTypeNib, forCellReuseIdentifier: "GameCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Колокольчик могли переключить на экране игры — перечитываем список.
        reload()
        refreshReleaseDates()
    }

    /// Даты релизов часто переносят — сверяем сохранённые игры с IGDB.
    private func refreshReleaseDates() {
        Task {
            let changed = await ReminderService.shared.refreshReleaseDates(using: gameService)
            guard !changed.isEmpty else { return }
            changedGameIDs.formUnion(changed)
            reload()
        }
    }

    private func reload() {
        games = ReminderService.shared.trackedGames
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        guard games.isEmpty else {
            tableView.backgroundView = nil
            return
        }

        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = String(localized: "Tap the bell on a game page to track its release")

        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32)
        ])

        tableView.backgroundView = container
    }

    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        games.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let game = games[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "GameCell", for: indexPath) as! GameCell
        cell.configure(with: game, showCountdown: true, dateChanged: changedGameIDs.contains(game.id))
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let detailViewController = GameDetailViewController(game: games[indexPath.row], gameService: gameService)
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let removeAction = UIContextualAction(
            style: .destructive,
            title: String(localized: "Remove")
        ) { [weak self] _, _, completion in
            guard let self else { return }
            ReminderService.shared.removeReminder(for: games[indexPath.row].id)
            games.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            updateEmptyState()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [removeAction])
    }

}
