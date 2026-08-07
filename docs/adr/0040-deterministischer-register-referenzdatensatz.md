# ADR 0040: Deterministischer Register-Referenzdatensatz und messbare Grenzwerte

## Status

Angenommen am 08.08.2026.

## Kontext

Die kleine UI-Demo deckte Persistenz, Berichte und Startverhalten großer
Finanzdateien nicht reproduzierbar ab. Private QIF-Dateien dürfen weder als
Testfixture noch als Repositoryinhalt verwendet werden.

## Entscheidung

`FinanceAppStore.seedReferenceRegisterDataset()` erzeugt ausschließlich in
einer leeren Finanzdatei feste Konten- und Buchungs-UUIDs. Der Datensatz
enthält 12 Konten in vier Standardgruppen, EUR/USD/CHF, 10.000 Buchungen über
3.653 Tage, genau 200 Splitzeilen und 150 ausgeglichene Umbuchungen. Ein
Manifest enthält Strukturzahlen, Datumsgrenzen und erwartete Berichtssummen.

`SQLiteFinanceStore.seedReferenceTransactions` validiert alle Zeilen vor dem
Commit und schreibt sie mit wiederverwendeten Prepared Statements in genau
einer SQLite-Transaktion. Buchungen, Splits und Tags werden beim Lesen mit vier
gebündelten Abfragen statt einer Abfrage je Buchung geladen. Fest formatierte
SQLite-Tage werden ohne `DateFormatter` als geprüfte gregorianische Tage
dekodiert.

Bei mehr als 25.000 Buchungen wird der globale Volltextindex nach dem
vollständigen Kernstart verzögert auf einer Utility-Task gebaut. Bis dahin
bleibt die korrekte direkte Dokumentprüfung verfügbar. Ein Generationswert
verhindert, dass ein veralteter Hintergrundindex einen neu geladenen Stand
überschreibt.

Der normale Test prüft Struktur, Persistenz, Umbuchungen, Splits,
Berichtssummen und SQLite-Integrität. Ein ausdrücklicher lokaler Opt-in-Lauf
erweitert auf 100.000 Buchungen und erzwingt die Mastergrenzen: Persistierung
unter 30 s, Startkern unter 3 s, Kontenblatt unter 500 ms und Standardbericht
unter 2 s. Die Nutzerabfrage des bereits aufgebauten Volltextindexes bleibt
ein eigener 100.000-Dokumente-Test mit 100-ms-Grenze.

## Folgen

Der große Test enthält keine persönlichen Daten und ist vollständig
reproduzierbar, läuft wegen Zeit und Speicher aber nicht standardmäßig. Der
Referenzdatensatz deckt zunächst den priorisierten Kontenblattkern ab; die
weiteren Master-Referenzbereiche bleiben in der Anforderungsmatrix offen.
