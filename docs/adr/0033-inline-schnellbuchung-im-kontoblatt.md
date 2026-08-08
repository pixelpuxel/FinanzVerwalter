# ADR 0033: Inline-Schnellbuchung im Kontoblatt

## Status

Angenommen am 07.08.2026.

## Kontext

Normale Buchungen mussten bisher denselben modalen Dialog wie Split-, Steuer-
oder Fremdwährungsbuchungen öffnen. Für die häufigste Registerarbeit verlangt
der Master-Prompt dagegen eine schnelle Inline-Eingabe, ohne den sicheren
Persistenz-, Audit- und Undo-Pfad zu umgehen.

## Entscheidung

Das Kontoblatt erhält eine einblendbare, horizontal scrollbare
Schnellbuchungszeile mit Datum, offenem Konto, Empfänger, Verwendungszweck,
vollständiger Kategorie, Status und Betrag. `RegisterQuickEntryDraft` prüft
Konto und Eingabe, normalisiert Texte und wertet den Betrag über
`Money(evaluating:)` in der Kontowährung aus. Der aufgelöste Wert erzeugt eine
einfache manuelle `FinanceTransaction` mit Wertstellung gleich Buchungsdatum,
ohne Transfer-/Importidentität, Splits, MwSt. oder Fremdwährung.

Gespeichert wird über `SQLiteFinanceStore.saveTransaction`; damit entstehen
Audit und persistentes konfliktgeschütztes Undo atomar wie im vollständigen
Dialog. Eingabe im Betragsfeld speichert, Esc verwirft den Entwurf und Tab
bleibt Standardnavigation. Nach Erfolg bleiben Datum und Konto erhalten,
während Inhaltsfelder geleert werden.

## Folgen

Die häufigste Buchung ist ohne modalen Kontextwechsel möglich. Komplexe
Fachzustände bleiben im vollständigen Dialog, sodass die Schnellzeile keine
zweite Split-, Steuer-, SEPA-, Anhangs- oder Fremdwährungsoberfläche werden
muss. Ein geschlossenes oder fehlendes Konto und jeder Parserfehler führen zu
keiner Teilmutation.
