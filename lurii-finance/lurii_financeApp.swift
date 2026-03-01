//
//  lurii_financeApp.swift
//  lurii-finance
//
//  Created by Chizhov Yurii on 28.02.2026.
//

import SwiftUI

@main
struct lurii_financeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
