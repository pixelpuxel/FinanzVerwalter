import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: Self { self }
    var title: String {
        switch self {
        case .light: "Hell"
        case .dark: "Dunkel"
        case .system: "System"
        }
    }
    var icon: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .system: "circle.lefthalf.filled"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

@main
struct FinanzVerwalterApp: App {
    @StateObject private var store = FinanceAppStore()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.light.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(
                    AppearanceMode(rawValue: appearanceMode)?.colorScheme ?? .light
                )
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Speichern") {
                    NotificationCenter.default.post(
                        name: .saveCurrentEditor,
                        object: nil
                    )
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Neue Buchung") {
                    NotificationCenter.default.post(name: .newTransaction, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Finanzen") {
                Button("Suchen") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Konto abgleichen") {
                    NotificationCenter.default.post(name: .reconcileAccount, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Buchung aufteilen") {
                    NotificationCenter.default.post(
                        name: .openSplitEditor,
                        object: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Auswahl als Filter übernehmen") {
                    NotificationCenter.default.post(
                        name: .filterRegisterSelection,
                        object: nil
                    )
                }
                .keyboardShortcut(
                    KeyEquivalent(Character("\u{F706}")),
                    modifiers: []
                )
            }
        }
    }
}

extension Notification.Name {
    static let newTransaction = Notification.Name("FinanzVerwalter.newTransaction")
    static let focusSearch = Notification.Name("FinanzVerwalter.focusSearch")
    static let reconcileAccount = Notification.Name("FinanzVerwalter.reconcileAccount")
    static let saveCurrentEditor = Notification.Name("FinanzVerwalter.saveCurrentEditor")
    static let openSplitEditor = Notification.Name("FinanzVerwalter.openSplitEditor")
    static let filterRegisterSelection = Notification.Name(
        "FinanzVerwalter.filterRegisterSelection"
    )
}
