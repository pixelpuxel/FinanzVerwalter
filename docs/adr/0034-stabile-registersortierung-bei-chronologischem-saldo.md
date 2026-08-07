# ADR 0034: Stabile Registersortierung bei chronologischem Saldo

## Status

Angenommen am 07.08.2026.

## Kontext

Das Kontoblatt zeigte Buchungen bisher nur in der gelieferten chronologischen
Reihenfolge. Der Master-Prompt verlangt eine Sortierung der Registerfelder.
Eine naive Neuberechnung des laufenden Saldos in der jeweils sichtbaren
Sortierung würde jedoch fachlich falsche Salden erzeugen.

## Entscheidung

`RegisterSorter` ordnet fertige Buchungszeilen auf- oder absteigend nach jeder
`RegisterColumn`. Für Kategorie, Klassen/Tags und Konto erhält er die bereits
vollständig aufgelösten sichtbaren Bezeichnungen. Deutsche Texte werden mit
`de_DE`, case- und diakritikaunabhängig sowie numerisch verglichen. Datum,
Wertstellung, Statusrang, Betrag und Saldo verwenden ihre typisierten Werte.
Gleichstände werden immer durch Buchungsdatum und UUID aufgelöst.

Die laufenden Salden werden vorher unverändert chronologisch je Konto
berechnet und anschließend nur als zeilenfeste Werte sortiert. Sortierspalte
und Richtung sind lokale Einstellungen und optionale Felder einer benannten
Kontoblattansicht. Fehlen sie in älteren Ansichten, gilt Datum aufsteigend.

## Folgen

Jede Standardspalte ist reproduzierbar sortierbar, ohne den fachlichen Saldo
zu verändern. CSV, PDF und Druck erhalten weiterhin exakt die sichtbare,
bereits sortierte Zeilenfolge. Das Menü ist tastatur- und
barrierefreiheitsfähig; eine spätere anklickbare Tabellenkopfsteuerung kann
dieselbe Sortierengine verwenden.
