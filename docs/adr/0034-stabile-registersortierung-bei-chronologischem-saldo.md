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

Jede dynamische `TableColumn` erhält zusätzlich einen
`RegisterTableComparator` über `sortUsing`; die Tabelle bindet ihr natives
`sortOrder` direkt an denselben persistenten Zustand. Dadurch wählt ein Klick
auf einen anderen Spaltenkopf diese Spalte aufsteigend, ein weiterer Klick
kehrt die Richtung um, und macOS liefert Richtungspfeil, Tastaturbedienung und
Accessibility-Semantik systemkonform.

## Folgen

Jede Standardspalte ist über Menü oder Tabellenkopf reproduzierbar sortierbar,
ohne den fachlichen Saldo zu verändern. CSV, PDF und Druck erhalten weiterhin
exakt die sichtbare, bereits sortierte Zeilenfolge. Menü, Tabellenkopf und
benannte Ansicht verwenden immer denselben Zustand.
