import AppKit
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
    @AppStorage(AppShortcutConfiguration.storageKey) private var shortcutData = ""

    private var shortcuts: AppShortcutConfiguration {
        AppShortcutCodec.decode(shortcutData)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .background(ContextualShortcutMonitorHost())
                .preferredColorScheme(
                    AppearanceMode(rawValue: appearanceMode)?.colorScheme ?? .light
                )
                .frame(minWidth: 960, minHeight: 640)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification
                    )
                ) { _ in
                    _ = store.createAutomaticBackup()
                }
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
                .keyboardShortcut(
                    shortcuts.binding(for: .save).key.equivalent,
                    modifiers: shortcuts.binding(for: .save).eventModifiers
                )
            }
            CommandGroup(replacing: .newItem) {
                Button("Neue Buchung") {
                    NotificationCenter.default.post(name: .newTransaction, object: nil)
                }
                .keyboardShortcut(
                    shortcuts.binding(for: .newTransaction).key.equivalent,
                    modifiers: shortcuts.binding(for: .newTransaction).eventModifiers
                )
            }
            CommandMenu("Finanzen") {
                Button("Suchen") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut(
                    shortcuts.binding(for: .search).key.equivalent,
                    modifiers: shortcuts.binding(for: .search).eventModifiers
                )
                Button("Konto abgleichen") {
                    NotificationCenter.default.post(name: .reconcileAccount, object: nil)
                }
                .keyboardShortcut(
                    shortcuts.binding(for: .reconcile).key.equivalent,
                    modifiers: shortcuts.binding(for: .reconcile).eventModifiers
                )
                Button("Buchung aufteilen") {
                    NotificationCenter.default.post(
                        name: .openSplitEditor,
                        object: nil
                    )
                }
                .keyboardShortcut(
                    shortcuts.binding(for: .split).key.equivalent,
                    modifiers: shortcuts.binding(for: .split).eventModifiers
                )
                Button("Als Vorlage merken") {
                    NotificationCenter.default.post(
                        name: .rememberTransactionTemplate,
                        object: nil
                    )
                }
                .keyboardShortcut(
                    shortcuts.binding(for: .rememberTemplate).key.equivalent,
                    modifiers: shortcuts.binding(for: .rememberTemplate).eventModifiers
                )
                Button("Auswahl als Filter übernehmen") {
                    NotificationCenter.default.post(
                        name: .filterRegisterSelection,
                        object: nil
                    )
                }
                .keyboardShortcut(
                    shortcuts.binding(for: .filterSelection).key.equivalent,
                    modifiers: shortcuts.binding(for: .filterSelection).eventModifiers
                )
                Divider()
                Button("Auswahl löschen") {
                    NotificationCenter.default.post(
                        name: .deleteRegisterSelection,
                        object: nil
                    )
                }
                Button("Übernehmen") {
                    NotificationCenter.default.post(name: .acceptCurrentEditor, object: nil)
                }
                Button("Abbrechen") {
                    NotificationCenter.default.post(name: .cancelCurrentEditor, object: nil)
                }
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
    static let rememberTransactionTemplate = Notification.Name(
        "FinanzVerwalter.rememberTransactionTemplate"
    )
    static let deleteRegisterSelection = Notification.Name(
        "FinanzVerwalter.deleteRegisterSelection"
    )
    static let acceptCurrentEditor = Notification.Name(
        "FinanzVerwalter.acceptCurrentEditor"
    )
    static let cancelCurrentEditor = Notification.Name(
        "FinanzVerwalter.cancelCurrentEditor"
    )
    static let openTransactionReport = Notification.Name(
        "FinanzVerwalter.openTransactionReport"
    )
}
