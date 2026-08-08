# ADR 0049: Fachauswertungen mit vollständigem Queryzustand auslagern

## Status

Angenommen am 08.08.2026.

## Kontext

Neben der freien Berichtswerkstatt besitzt FinanzVerwalter sieben
spezialisierte Berichte mit jeweils eigenem Filtermodell. Für einen
Desktop-Arbeitsablauf müssen auch diese Berichte parallel sichtbar sein,
ohne Filter beim Öffnen eines zweiten Fensters zu verlieren oder versehentlich
auf eine andere Finanzdatei anzuwenden.

## Entscheidung

Alle sieben Querytypen sind codierbar. Eine
`SpecializedReportWindowRequest` kapselt Fachberichtstyp, vollständigen
Payload, kanonischen Finanzdateipfad und eine frische UUID. Der Budgetbericht
ergänzt seine Query um die ausgewählte Budget-ID. Ein typisiertes
SwiftUI-`WindowGroup` dekodiert den zum Typ gehörenden Payload und
rekonstruiert die spezialisierte Ansicht mit sämtlichen Filtern.

Vor der Darstellung wird der gespeicherte Pfad mit der aktiven Finanzdatei
verglichen. Typfremde oder beschädigte Payloads erhalten einen getrennten
Fehlerzustand. Der Frame-Autosave-Name wird aus Berichtstyp und UUID gebildet.

## Folgen

- Gleiche Fachabfragen lassen sich bewusst in mehreren Fenstern öffnen.
- Filter, Export- und Druckkontext bleiben je Fenster unabhängig.
- Ein Dateidwechsel kann keine Abfrage still auf fremde Daten anwenden.
- Neue Fachberichtstypen benötigen einen codierbaren Payload und einen
  expliziten Dekodierungszweig.
- Die Rückintegration ins Hauptfenster bleibt eine getrennte Ausbaustufe.
