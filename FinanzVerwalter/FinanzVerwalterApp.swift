import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
                .background(MainWindowRegistrationHost())
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
                Divider()
                Button("Neue Finanzdatei …") {
                    createFinanceFile()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Finanzdatei öffnen …") {
                    openFinanceFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                Menu("Zuletzt verwendete Finanzdateien") {
                    if store.recentFinanceFileURLs.isEmpty {
                        Text("Keine zuletzt verwendeten Dateien")
                    } else {
                        ForEach(store.recentFinanceFileURLs, id: \.path) { url in
                            Button(url.lastPathComponent) {
                                prepareForFinanceFileChange()
                                _ = store.openFinanceFile(at: url)
                            }
                            .help(url.path)
                        }
                    }
                }
                Divider()
                Button("Kopie der Finanzdatei erstellen …") {
                    createFinanceFileCopy()
                }
                .disabled(store.currentFinanceFileURL == nil)
                Button("Finanzdatei archivieren …") {
                    archiveFinanceFile()
                }
                .disabled(store.currentFinanceFileURL == nil)
                Divider()
                Button("Finanzdatei schließen") {
                    closeFinanceFile()
                }
                .disabled(store.currentFinanceFileURL == nil)
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

        WindowGroup("Auswertung", for: ReportWindowRequest.self) { request in
            ExternalReportWindow(request: request.wrappedValue)
                .environmentObject(store)
                .background(ContextualShortcutMonitorHost())
                .background(
                    WindowFrameAutosaveHost(
                        name: request.wrappedValue?.frameAutosaveName
                            ?? "FinanzVerwalter.Auswertung.Leer"
                    )
                )
                .preferredColorScheme(
                    AppearanceMode(rawValue: appearanceMode)?.colorScheme ?? .light
                )
        }
        .defaultSize(width: 1380, height: 860)
    }

    private var financeFileType: UTType {
        UTType(filenameExtension: "qdata") ?? .data
    }

    private func prepareForFinanceFileChange() {
        NotificationCenter.default.post(name: .cancelCurrentEditor, object: nil)
    }

    private func openFinanceFile() {
        let panel = NSOpenPanel()
        panel.title = "Finanzdatei öffnen"
        panel.prompt = "Öffnen"
        panel.allowedContentTypes = [financeFileType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prepareForFinanceFileChange()
        _ = store.openFinanceFile(at: url)
    }

    private func createFinanceFile() {
        let panel = NSSavePanel()
        panel.title = "Neue Finanzdatei anlegen"
        panel.prompt = "Anlegen"
        panel.allowedContentTypes = [financeFileType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Neue Finanzen.qdata"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension.lowercased() != "qdata" {
            url.appendPathExtension("qdata")
        }
        let displayName = url.deletingPathExtension().lastPathComponent
        prepareForFinanceFileChange()
        _ = store.createFinanceFile(at: url, name: displayName)
    }

    private func createFinanceFileCopy() {
        guard let source = store.currentFinanceFileURL else { return }
        let panel = NSSavePanel()
        panel.title = "Kopie der Finanzdatei erstellen"
        panel.prompt = "Kopie erstellen"
        panel.allowedContentTypes = [financeFileType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            "\(source.deletingPathExtension().lastPathComponent) Kopie.qdata"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension.lowercased() != "qdata" {
            url.appendPathExtension("qdata")
        }
        _ = store.createFinanceFileCopy(at: url)
    }

    private func archiveFinanceFile() {
        guard let source = store.currentFinanceFileURL else { return }
        let archiveType = UTType(filenameExtension: "qarchive") ?? .data
        let panel = NSSavePanel()
        panel.title = "Finanzdatei archivieren"
        panel.prompt = "Archivieren"
        panel.allowedContentTypes = [archiveType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            "\(source.deletingPathExtension().lastPathComponent) Archiv.qarchive"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension.lowercased() != "qarchive" {
            url.appendPathExtension("qarchive")
        }
        _ = store.archiveFinanceFile(at: url)
    }

    private func closeFinanceFile() {
        let alert = NSAlert()
        alert.messageText = "Finanzdatei schließen?"
        alert.informativeText =
            "Vor dem Schließen wird automatisch eine geprüfte Sicherung erstellt."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Schließen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        prepareForFinanceFileChange()
        _ = store.closeFinanceFile()
    }
}

@MainActor
final class MainWindowCoordinator {
    static let shared = MainWindowCoordinator()
    weak var window: NSWindow?

    func activate() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MainWindowRegistrationHost: NSViewRepresentable {
    final class HostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                MainWindowCoordinator.shared.window = window
            }
        }
    }

    func makeNSView(context: Context) -> HostView { HostView() }
    func updateNSView(_ nsView: HostView, context: Context) {}
}

struct WindowFrameAutosaveHost: NSViewRepresentable {
    final class HostView: NSView {
        var autosaveName = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAutosaveName()
        }

        func applyAutosaveName() {
            guard !autosaveName.isEmpty, let window else { return }
            window.setFrameAutosaveName(autosaveName)
        }
    }

    let name: String

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.autosaveName = name
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        nsView.autosaveName = name
        nsView.applyAutosaveName()
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
    static let openAccountRegister = Notification.Name(
        "FinanzVerwalter.openAccountRegister"
    )
    static let openAccountBanking = Notification.Name(
        "FinanzVerwalter.openAccountBanking"
    )
    static let financeFileDidChange = Notification.Name(
        "FinanzVerwalter.financeFileDidChange"
    )
}
