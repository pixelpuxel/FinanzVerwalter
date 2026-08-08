# ADR 0004: Dynamische Kontoblattspalten ab macOS 14.4

- Status: angenommen
- Datum: 31.07.2026

## Kontext

Kontoblatt und Sammelkontoblatt benötigen wirklich ein- und ausblendbare
Spalten. Ein bloßes Verbergen des Zellinhalts lässt leere Tabellenköpfe und
Spaltenbreiten zurück und erfüllt die Bedienanforderung nicht. SwiftUI stellt
bedingte beziehungsweise datengetriebene `TableColumn`-Inhalte erst ab
macOS 14.4 bereit. Der Zielrechner läuft auf macOS 26.

## Entscheidung

Das Mindestziel wird von macOS 14.0 auf macOS 14.4 angehoben.
`TableColumnForEach` erzeugt ausschließlich die ausgewählten Spalten.
Spaltenauswahl, Zeilenmodus und benannte Kontoblatt-Ansichten werden als
versionierte, fehlertolerant dekodierte Benutzereinstellung gespeichert.
Finanzdaten und ihre SQLite-Schemaversion bleiben davon unberührt.

## Folgen

- Ausgeblendete Spalten verschwinden vollständig einschließlich Tabellenkopf.
- Konto- und Sammelkontoblatt verwenden dieselbe dauerhafte Spaltenauswahl.
- Mindestens eine Spalte bleibt immer sichtbar; beschädigte oder leere
  Einstellungen fallen auf alle Standardspalten zurück.
- macOS 14.0 bis 14.3 werden nicht mehr unterstützt.
