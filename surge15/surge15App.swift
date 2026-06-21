//
//  surge15App.swift
//  surge15
//
//  Created by Anthony Hamill on 6/20/26.
//

import SwiftUI
import SwiftData

@main
struct surge15App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Route.self,
            RoutePoint.self,
            RouteSegment.self,
            Session.self,
            SessionPoint.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
