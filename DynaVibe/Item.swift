//
//  Item.swift
//  DynaVibe
//
//  Created by Jianhui Zhou on 2025-04-25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
