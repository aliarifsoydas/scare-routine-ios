//
//  SCare_RoutineApp.swift
//  SCare Routine
//
//  Created by aaStudio on 17.05.2026.
//

import SwiftUI
import SwiftData

@main
struct SCare_RoutineApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            self.modelContainer = try SCareSchema.makeContainer()
        } catch {
            fatalError("ModelContainer kurulamadı: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
