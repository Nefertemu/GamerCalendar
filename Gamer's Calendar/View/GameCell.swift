//
//  GameCell.swift
//  Gamer's Calendar
//
//  Created by Богдан Анищенков on 04.05.2022.
//

import UIKit

class GameCell: UITableViewCell {
    
    @IBOutlet var gameTitile: UILabel!
    @IBOutlet var releaseDate: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
}
