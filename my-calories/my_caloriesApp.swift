//
//  my_caloriesApp.swift
//  my-calories
//
//  Created by Noah on 8/27/26.
//

import SwiftUI
import SwiftData

@main
struct my_caloriesApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FoodEntry.self,
            FoodCatalogItem.self,
            UserProfile.self,
        ])

        let persistentConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [persistentConfiguration])
        } catch {
            // Recovery path for incompatible/corrupted stores after schema changes.
            let appSupport = URL.applicationSupportDirectory
            let candidateStoreFiles = [
                appSupport.appending(path: "default.store"),
                appSupport.appending(path: "default.store-shm"),
                appSupport.appending(path: "default.store-wal")
            ]
            for fileURL in candidateStoreFiles {
                try? FileManager.default.removeItem(at: fileURL)
            }

            do {
                return try ModelContainer(for: schema, configurations: [persistentConfiguration])
            } catch {
                let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
                } catch {
                    preconditionFailure("Could not create ModelContainer after recovery attempts: \(error)")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
