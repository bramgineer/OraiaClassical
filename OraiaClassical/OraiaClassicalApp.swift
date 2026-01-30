//
//  OraiaClassicalApp.swift
//  OraiaClassical
//
//  Created by verdi65 on 1/24/26.
//

import SwiftUI

@main
struct OraiaClassicalApp: App {
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environment(\.theme, themeManager.currentTheme)
        }
    }
}
