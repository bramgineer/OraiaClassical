//
//  OraiaClassicalApp.swift
//  OraiaClassical
//
//  Created by verdi65 on 1/24/26.
//

import SwiftUI
import UIKit

@main
struct OraiaClassicalApp: App {
    @StateObject private var themeManager = ThemeManager()

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.omega.background)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.omega.text)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.omega.text)]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environment(\.theme, themeManager.currentTheme)
        }
    }
}
