# ADR 0008: Konfigurierbare Shortcuts und dateigebundene Buchungsvorlagen

## Status

Angenommen am 31.07.2026.

## Kontext

Der Master-Prompt verlangt, dass alle zentralen Kontoblattbefehle sichtbar
und anpassbar sind. Globale, fest verdrahtete SwiftUI-Key-Equivalents
reichen dafür nicht. Insbesondere dürfen `Entfernen`, `Eingabe` und `Esc`
nicht unbesehen die Texteingabe eines aktiven Feldeditors übersteuern.
`Als Vorlage merken` benötigt außerdem eine echte, an die geöffnete
Finanzdatei gebundene Persistenz.

## Entscheidung

- `AppShortcutConfiguration` speichert zehn versionierte Zuordnungen aus
  Aktion, Taste und den Modifikatoren Command, Shift, Option und Control.
- Der Codec ergänzt fehlende Aktionen aus den Standardwerten und verwirft
  beschädigte, doppelte oder beim Tippen unsichere Konfigurationen.
  Buchstaben, Ziffern und Leertaste benötigen mindestens einen Modifikator.
- Normale Befehle erhalten dynamische Menü-Key-Equivalents. Die
  kontextabhängigen Befehle Löschen, Übernehmen und Abbrechen laufen über
  einen lokalen AppKit-Ereignismonitor. In einem aktiven `NSTextView`
  bleibt Entfernen immer dem Texteditor vorbehalten.
- Buchungsvorlagen liegen ab Schema 17 in `transaction_templates`. Der
  Payload wird deterministisch als versionierbare JSON-Struktur innerhalb
  der SQLite-Finanzdatei gespeichert. Konto, Betrag, Empfänger, Kategorie,
  Status, Memo, Tags und Splits werden übernommen; Datum, Belegnummer,
  Transfer- und Importidentität nie.
- Eine abgeglichene oder stornierte Quellbuchung wird in der Vorlage wieder
  zu `Gebucht`. Umbuchungsseiten werden nicht als irreführende Einzelvorlage
  zugelassen. Jede Verwendung erzeugt neue Buchungs- und Split-IDs.
- Mehrfachlöschen prüft die vollständige Auswahl sowie beide Seiten einer
  Umbuchung vor der ersten Änderung. Abgeglichene Buchungen sperren den
  gesamten Vorgang; erst nach ausdrücklicher Bestätigung wird atomar
  gelöscht und auditiert.

## Folgen

Die Belegung reagiert nach dem Anwenden ohne Neustart und bleibt
reproduzierbar testbar. Vorlagen wandern mit Sicherung und Restore der
Finanzdatei. Eine künftige Windows-Oberfläche kann dasselbe Aktionsmodell
verwenden, muss aber Plattformmodifikatoren separat abbilden.
