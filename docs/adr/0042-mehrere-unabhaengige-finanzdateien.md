# ADR 0042: Mehrere unabhängige Finanzdateien

## Status

Angenommen am 08.08.2026.

## Kontext

Verschiedene Haushalte, Vereine oder Mandate dürfen ihre Konten, Kategorien
und Buchungen nicht in derselben Finanzdatei vermischen. Eine globale
Standarddatei allein erfüllt diesen klassischen Desktop-Arbeitsablauf nicht.

## Entscheidung

Jede `.qdata`-Datei ist eine vollständige, eigenständige SQLite-Datenbank.
`FinanceAppStore` besitzt genau eine aktive `SQLiteFinanceStore`-Instanz und
wechselt sie transaktional auf Anwendungsebene: Kandidat öffnen und migrieren,
alte Datei online sichern, Kandidat vollständig laden, dann alte Verbindung
schließen. Bei einem Fehler wird der Kandidat geschlossen und die alte Datei
erneut geladen.

Nur reguläre, direkte `.qdata`-Dateien dürfen geöffnet werden. Neue Ziele
müssen fehlen und in einem direkten Verzeichnis liegen. Der letzte Pfad und
eine auf zehn Einträge begrenzte MRU-Liste liegen in `UserDefaults`; Fach- und
Finanzdaten bleiben ausschließlich in der jeweiligen SQLite-Datei. Demo- und
Testmodi schreiben diese Auswahl nicht.

## Folgen

- Datenbestände bleiben physisch und logisch getrennt.
- Jeder Wechsel erzeugt vorab eine wiederherstellbare Sicherung.
- Beschädigte, symbolisch umgeleitete oder falsch benannte Ziele verändern
  den aktiven Bestand nicht.
- Gleichzeitiges Bearbeiten mehrerer Dateien in mehreren App-Fenstern ist
  nicht Bestandteil dieser Entscheidung.
