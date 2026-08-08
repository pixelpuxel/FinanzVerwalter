# ADR 0002: Festkommawerte und transaktionales SQLite

- Status: angenommen
- Datum: 31.07.2026

## Kontext

Finanzdaten dürfen keine binäre Fließkomma-Drift besitzen. Splits, Transfers,
Lots, Budgets und Zahlungsaufträge benötigen reproduzierbare Rundung und
atomare Änderungen.

## Entscheidung

- Geld wird als `Int64` in währungsspezifischen Minor-Units gespeichert.
- Stückzahlen verwenden `Int64`-Mikroeinheiten.
- Prozentallokationen verwenden ganzzahlige Basispunkte.
- Eingabe und abgeleitete Berechnungen verwenden `Decimal` mit expliziter
  Rundung.
- SQLite läuft mit Foreign Keys, WAL und `synchronous=FULL`.
- Finanzielle Mehrfachänderungen laufen in einer SQLite-Transaktion und
  erzeugen ein Auditereignis.

## Folgen

Invarianten lassen sich exakt testen. Fremdwährungswechselkurse benötigen
noch ein eigenes Festkommaformat mit bis zu acht Nachkommastellen; diese
Erweiterung ist nicht durch das vorhandene Geldmodell vorweggenommen.
