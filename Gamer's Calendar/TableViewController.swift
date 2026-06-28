
import UIKit

class TableViewController: UITableViewController {
    
    private var games: [GamesStorage] = []
    private let rawgService = RawgService()
        
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = 112

        let cellTypeNib = UINib(nibName: "GameCell", bundle: nil)
        tableView.register(cellTypeNib, forCellReuseIdentifier: "GameCell")
        
        Task {
            do {
                games = try await rawgService.fetchGames()
                games.sort { ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture) }

                await MainActor.run {
                    tableView.reloadData()
                }
            } catch {
                print("RAWG loading error:", error)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "GameCell", for: indexPath) as! GameCell
        let gameTitle = cell.viewWithTag(1) as? UILabel
        let gameDate = cell.viewWithTag(2) as? UILabel
        let gameImage = cell.viewWithTag(3) as? UIImageView
        let gamePlatform = cell.viewWithTag(4) as? UILabel
        let game = games[indexPath.row]

        gameTitle?.text = game.gameTitle
        gamePlatform?.text = game.platforms.isEmpty ? "Unknown platform" : game.platforms
        gameDate?.text = game.releaseDate?.formatted(date: .numeric, time: .omitted) ?? "Unknown date"
        gameImage?.contentMode = .scaleAspectFill
        gameImage?.clipsToBounds = true
        gameImage?.image = UIImage(systemName: "photo")

        if let imageURL = game.imageURL {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: imageURL),
                      let image = UIImage(data: data) else {
                    return
                }

                await MainActor.run {
                    let currentCell = tableView.cellForRow(at: indexPath)
                    let currentImageView = currentCell?.viewWithTag(3) as? UIImageView
                    currentImageView?.image = image
                }
            }
        }

        return cell
    }
    
    private func getConfiguredTaskCell_constraints(for indexPath: IndexPath) -> UITableViewCell {
    // загружаем прототип ячейки по идентификатору
    let cell = tableView.dequeueReusableCell(withIdentifier: "GameCell", for: indexPath)
    return cell }
    
    // Uncomment the following line to preserve selection between presentations
    // self.clearsSelectionOnViewWillAppear = false
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return games.count
    }
    
    /*
     
     */
    
    /*
     // Override to support conditional editing of the table view.
     override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
     // Return false if you do not want the item to be editable.
     return true
     }
     */
    
    /*
     // Override to support editing the table view.
     override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
     if editingStyle == .delete {
     // Delete the row from the data source
     tableView.deleteRows(at: [indexPath], with: .fade)
     } else if editingStyle == .insert {
     // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
     }
     }
     */
    
    /*
     // Override to support rearranging of the table view.
     override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {
     
     }
     */
    
    /*
     // Override to support conditional rearranging of the table view.
     override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
     // Return false if you do not want the item to be re-orderable.
     return true
     }
     */
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destination.
     // Pass the selected object to the new view controller.
     }
     */
    
}
