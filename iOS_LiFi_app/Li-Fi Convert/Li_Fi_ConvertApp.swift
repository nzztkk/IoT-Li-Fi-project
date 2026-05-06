//
//  Li_Fi_ConvertApp.swift
//  Li-Fi Convert
//
//  Created by Nurkhat on 31.03.2026.
//

import SwiftUI
import CoreData

@main
struct Li_Fi_ConvertApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
