//
//  lurii_financeApp.swift
//  lurii-finance
//
//  Created by Chizhov Yurii on 28.02.2026.
//

import ServiceManagement
import SwiftUI

@main
struct lurii_financeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear { registerLoginItemIfNeeded() }
        }
    }

    private func registerLoginItemIfNeeded() {
        let service = SMAppService.mainApp
        if service.status == .notRegistered {
            try? service.register()
        }
    }
}
