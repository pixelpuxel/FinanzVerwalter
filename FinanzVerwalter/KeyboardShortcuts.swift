import AppKit
import SwiftUI

enum AppShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case newTransaction
    case save
    case search
    case reconcile
    case split
    case rememberTemplate
    case filterSelection
    case deleteSelection
    case accept
    case cancel

    var id: Self { self }

    var title: String {
        switch self {
        case .newTransaction: "Neue Buchung"
        case .save: "Speichern"
        case .search: "Suchen"
        case .reconcile: "Konto abgleichen"
        case .split: "Buchung aufteilen"
        case .rememberTemplate: "Als Vorlage merken"
        case .filterSelection: "Auswahl als Filter übernehmen"
        case .deleteSelection: "Auswahl löschen"
        case .accept: "Übernehmen"
        case .cancel: "Abbrechen"
        }
    }

    var helpText: String {
        switch self {
        case .newTransaction: "Öffnet eine neue Buchung."
        case .save: "Speichert den aktuell geöffneten Editor."
        case .search: "Setzt den Fokus in die globale Suche."
        case .reconcile: "Öffnet den Kontoabgleich."
        case .split: "Öffnet eine neue Splitbuchung oder teilt den aktuellen Entwurf."
        case .rememberTemplate: "Merkt die markierte Buchung als wiederverwendbaren Entwurf."
        case .filterSelection: "Übernimmt das gewählte Feld der markierten Buchung als Filter."
        case .deleteSelection: "Prüft und löscht die markierten Buchungen nach Bestätigung."
        case .accept: "Übernimmt den aktuell geöffneten Dialog."
        case .cancel: "Bricht den aktuell geöffneten Dialog ab."
        }
    }
}

enum ShortcutModifier: String, CaseIterable, Codable, Identifiable, Sendable {
    case command
    case shift
    case option
    case control

    var id: Self { self }

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .shift: "⇧"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    var eventModifier: EventModifiers {
        switch self {
        case .command: .command
        case .shift: .shift
        case .option: .option
        case .control: .control
        }
    }
}

enum ShortcutKey: String, CaseIterable, Codable, Identifiable, Sendable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case zero, one, two, three, four, five, six, seven, eight, nine
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case delete, returnKey, escape, space

    var id: Self { self }

    var title: String {
        switch self {
        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        case .delete: "Entfernen"
        case .returnKey: "Eingabe"
        case .escape: "Esc"
        case .space: "Leertaste"
        default: rawValue.uppercased()
        }
    }

    var equivalent: KeyEquivalent {
        switch self {
        case .zero: return KeyEquivalent("0")
        case .one: return KeyEquivalent("1")
        case .two: return KeyEquivalent("2")
        case .three: return KeyEquivalent("3")
        case .four: return KeyEquivalent("4")
        case .five: return KeyEquivalent("5")
        case .six: return KeyEquivalent("6")
        case .seven: return KeyEquivalent("7")
        case .eight: return KeyEquivalent("8")
        case .nine: return KeyEquivalent("9")
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
            return KeyEquivalent(Character(UnicodeScalar(0xF704 + functionKeyNumber - 1)!))
        case .delete: return .delete
        case .returnKey: return .return
        case .escape: return .escape
        case .space: return .space
        default: return KeyEquivalent(Character(rawValue))
        }
    }

    private var functionKeyNumber: Int {
        Int(rawValue.dropFirst()) ?? 1
    }

    var requiresModifier: Bool {
        switch self {
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
             .delete, .returnKey, .escape:
            false
        default:
            true
        }
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers else { return false }
        switch self {
        case .zero: return characters == "0"
        case .one: return characters == "1"
        case .two: return characters == "2"
        case .three: return characters == "3"
        case .four: return characters == "4"
        case .five: return characters == "5"
        case .six: return characters == "6"
        case .seven: return characters == "7"
        case .eight: return characters == "8"
        case .nine: return characters == "9"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
            return characters.unicodeScalars.first?.value
                == UInt32(0xF704 + functionKeyNumber - 1)
        case .delete:
            return characters == "\u{7F}" || characters == "\u{8}"
        case .returnKey:
            return characters == "\r" || characters == "\n"
        case .escape:
            return characters == "\u{1B}"
        case .space:
            return characters == " "
        default:
            return characters.localizedLowercase == rawValue
        }
    }
}

struct AppShortcutBinding: Codable, Equatable, Hashable, Sendable {
    var key: ShortcutKey
    var modifiers: Set<ShortcutModifier>

    var eventModifiers: EventModifiers {
        modifiers.reduce(into: EventModifiers()) {
            $0.insert($1.eventModifier)
        }
    }

    var displayText: String {
        ShortcutModifier.allCases
            .filter(modifiers.contains)
            .map(\.symbol)
            .joined()
            + key.title
    }
}

struct AppShortcutAssignment: Codable, Equatable, Sendable {
    var action: AppShortcutAction
    var binding: AppShortcutBinding
}

struct AppShortcutConfiguration: Codable, Equatable, Sendable {
    static let storageKey = "appKeyboardShortcutsV1"

    var version: Int
    var assignments: [AppShortcutAssignment]

    static let defaults = AppShortcutConfiguration(
        version: 1,
        assignments: [
            .init(action: .newTransaction, binding: .init(key: .n, modifiers: [.command])),
            .init(action: .save, binding: .init(key: .s, modifiers: [.command])),
            .init(action: .search, binding: .init(key: .f, modifiers: [.command])),
            .init(action: .reconcile, binding: .init(key: .r, modifiers: [.command])),
            .init(action: .split, binding: .init(key: .s, modifiers: [.command, .shift])),
            .init(action: .rememberTemplate, binding: .init(key: .m, modifiers: [.command])),
            .init(action: .filterSelection, binding: .init(key: .f3, modifiers: [])),
            .init(action: .deleteSelection, binding: .init(key: .delete, modifiers: [])),
            .init(action: .accept, binding: .init(key: .returnKey, modifiers: [])),
            .init(action: .cancel, binding: .init(key: .escape, modifiers: []))
        ]
    )

    func binding(for action: AppShortcutAction) -> AppShortcutBinding {
        assignments.first { $0.action == action }?.binding
            ?? Self.defaults.assignments.first { $0.action == action }!.binding
    }

    mutating func set(_ binding: AppShortcutBinding, for action: AppShortcutAction) {
        assignments.removeAll { $0.action == action }
        assignments.append(.init(action: action, binding: binding))
        assignments.sort {
            AppShortcutAction.allCases.firstIndex(of: $0.action)!
                < AppShortcutAction.allCases.firstIndex(of: $1.action)!
        }
    }

    var conflicts: [[AppShortcutAction]] {
        Dictionary(grouping: AppShortcutAction.allCases) {
            binding(for: $0)
        }
        .values
        .filter { $0.count > 1 }
        .map {
            $0.sorted {
                AppShortcutAction.allCases.firstIndex(of: $0)!
                    < AppShortcutAction.allCases.firstIndex(of: $1)!
            }
        }
    }

    var barePrintableActions: Set<AppShortcutAction> {
        Set(AppShortcutAction.allCases.filter {
            let value = binding(for: $0)
            return value.key.requiresModifier && value.modifiers.isEmpty
        })
    }

    var isValid: Bool {
        conflicts.isEmpty && barePrintableActions.isEmpty
    }
}

enum AppShortcutCodec {
    static func decode(_ raw: String) -> AppShortcutConfiguration {
        guard
            let data = raw.data(using: .utf8),
            var decoded = try? JSONDecoder().decode(AppShortcutConfiguration.self, from: data),
            decoded.version == 1
        else {
            return .defaults
        }
        for action in AppShortcutAction.allCases where
            !decoded.assignments.contains(where: { $0.action == action }) {
            decoded.set(AppShortcutConfiguration.defaults.binding(for: action), for: action)
        }
        var seen = Set<AppShortcutAction>()
        decoded.assignments = decoded.assignments.filter { seen.insert($0.action).inserted }
        return decoded.isValid ? decoded : .defaults
    }

    static func encode(_ value: AppShortcutConfiguration) -> String {
        guard value.isValid,
              let data = try? JSONEncoder().encode(value)
        else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

@MainActor
final class ContextualShortcutMonitor {
    static let shared = ContextualShortcutMonitor()

    private var token: Any?
    private var configuration = AppShortcutConfiguration.defaults
    private let actions: [AppShortcutAction] = [
        .deleteSelection, .accept, .cancel
    ]

    func start(configuration: AppShortcutConfiguration) {
        self.configuration = configuration
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = shortcutModifiers(event.modifierFlags)
        guard let action = actions.first(where: {
            let binding = configuration.binding(for: $0)
            return binding.modifiers == modifiers && binding.key.matches(event)
        }) else {
            return event
        }
        if action == .deleteSelection,
           event.window?.firstResponder is NSTextView {
            return event
        }
        let name: Notification.Name
        switch action {
        case .deleteSelection: name = .deleteRegisterSelection
        case .accept: name = .acceptCurrentEditor
        case .cancel: name = .cancelCurrentEditor
        default: return event
        }
        NotificationCenter.default.post(name: name, object: nil)
        return nil
    }

    private func shortcutModifiers(
        _ flags: NSEvent.ModifierFlags
    ) -> Set<ShortcutModifier> {
        var result = Set<ShortcutModifier>()
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
}

struct ContextualShortcutMonitorHost: View {
    @AppStorage(AppShortcutConfiguration.storageKey) private var storedValue = ""

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                ContextualShortcutMonitor.shared.start(
                    configuration: AppShortcutCodec.decode(storedValue)
                )
            }
            .onChange(of: storedValue) {
                ContextualShortcutMonitor.shared.start(
                    configuration: AppShortcutCodec.decode(storedValue)
                )
            }
    }
}

struct ShortcutSettingsSection: View {
    @AppStorage(AppShortcutConfiguration.storageKey) private var storedValue = ""
    @State private var draft = AppShortcutConfiguration.defaults
    @State private var didLoad = false

    private var conflictActions: Set<AppShortcutAction> {
        Set(draft.conflicts.flatMap { $0 })
    }

    var body: some View {
        Section("Tastaturkurzbefehle") {
            ForEach(AppShortcutAction.allCases) { action in
                let binding = draft.binding(for: action)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                            Text(action.helpText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker(
                            "Taste",
                            selection: Binding(
                                get: { binding.key },
                                set: {
                                    var changed = draft.binding(for: action)
                                    changed.key = $0
                                    draft.set(changed, for: action)
                                }
                            )
                        ) {
                            ForEach(ShortcutKey.allCases) { key in
                                Text(key.title).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        HStack(spacing: 4) {
                            ForEach(ShortcutModifier.allCases) { modifier in
                                Toggle(
                                    modifier.symbol,
                                    isOn: Binding(
                                        get: { binding.modifiers.contains(modifier) },
                                        set: { enabled in
                                            var changed = draft.binding(for: action)
                                            if enabled {
                                                changed.modifiers.insert(modifier)
                                            } else {
                                                changed.modifiers.remove(modifier)
                                            }
                                            draft.set(changed, for: action)
                                        }
                                    )
                                )
                                .toggleStyle(.button)
                                .help(modifier.rawValue)
                            }
                        }
                        Text(binding.displayText)
                            .font(.body.monospaced())
                            .frame(width: 70, alignment: .trailing)
                    }
                    if conflictActions.contains(action) {
                        Label(
                            "Diese Belegung ist mehrfach vergeben.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    if draft.barePrintableActions.contains(action) {
                        Label(
                            "Buchstaben, Zahlen und Leertaste benötigen mindestens eine Zusatztaste.",
                            systemImage: "keyboard.badge.ellipsis"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(action.title), \(binding.displayText)")
            }
            HStack {
                Button("Standard wiederherstellen") {
                    draft = .defaults
                }
                Spacer()
                Button("Kurzbefehle anwenden") {
                    storedValue = AppShortcutCodec.encode(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
            Text(
                draft.isValid
                    ? "Änderungen gelten sofort für Menüleiste und Register."
                    : "Behebe doppelte oder beim Tippen unsichere Tastenkombinationen."
            )
            .font(.caption)
            .foregroundStyle(draft.isValid ? Color.secondary : Color.red)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draft = AppShortcutCodec.decode(storedValue)
        }
    }
}
