//
//  Theme.swift
//  OraiaClassical
//
//  Created by verdi65 on 1/30/26.
//

import SwiftUI

struct Theme {
    let name: String
    let primary: Color      // for symbols, icons
    let background: Color   // parchment
    let surface: Color      // cards and grouped sections
    let surfaceAlt: Color   // fields and inner rows
    let text: Color         // main text
    let accent: Color       // highlights
    let font: Font          // body style
}

extension Theme {
    static let omega = Theme(
        name: "Omega",
        primary: Color(red: 43/255, green: 28/255, blue: 19/255),     // #2B1C13
        background: Color(red: 214/255, green: 184/255, blue: 141/255), // #D6B88D
        surface: Color(red: 231/255, green: 209/255, blue: 170/255),    // #E7D1AA
        surfaceAlt: Color(red: 243/255, green: 229/255, blue: 205/255), // #F3E5CD
        text: Color(red: 43/255, green: 28/255, blue: 19/255),
        accent: Color(red: 201/255, green: 151/255, blue: 0/255),     // #C99700
        font: .custom("Georgia", size: 18) // Replace with custom font if desired
    )
}
let forestGreen = Color(red: 34 / 255, green: 139 / 255, blue: 34 / 255)

final class ThemeManager: ObservableObject {
    @Published var currentTheme: Theme = .omega
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .omega
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

private struct ThemedAppModifier: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .font(theme.font)
            .foregroundStyle(theme.text)
            .tint(theme.accent)
            .background(theme.background.ignoresSafeArea())
    }
}

extension View {
    func themedApp() -> some View {
        modifier(ThemedAppModifier())
    }
}

extension View {
    func omegaFont(_ theme: Theme) -> some View {
        self.font(theme.font)
    }

    func omegaForeground(_ theme: Theme) -> some View {
        self.foregroundColor(theme.text)
    }

    func omegaBackground(_ theme: Theme) -> some View {
        self.background(theme.background)
    }

    func omegaPrimary(_ theme: Theme) -> some View {
        self.foregroundColor(theme.primary)
    }

    func omegaAccent(_ theme: Theme) -> some View {
        self.foregroundColor(theme.accent)
    }
}
