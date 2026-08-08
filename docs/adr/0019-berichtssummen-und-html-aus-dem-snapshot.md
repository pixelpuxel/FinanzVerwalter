# ADR 0019: Berichtssummen und HTML aus demselben Snapshot

## Status

Angenommen am 07.08.2026.

## Kontext

Zweistufig gruppierte Berichte benötigen nachvollziehbare Zwischensummen. Die
Bildschirmansicht und alle Exporte dürfen dafür weder eigene Buchungsabfragen
noch voneinander abweichende Summen berechnen. Alte gespeicherte Vorlagen
enthalten keine Darstellungsschalter.

## Entscheidung

`TransactionReportEngine` erzeugt währungsgetrennte Detailgruppen und direkt
danach eine Primär-Zwischensumme, deren Fakten-IDs die Vereinigung ihrer
Detailgruppen sind. Der unveränderliche Snapshot trägt außerdem die Schalter
für Buchungsdetails, Zwischen- und Gesamtsummen. Fehlende optionale Felder in
älterem Query-JSON bedeuten jeweils `true`.

CSV, PDF und HTML rendern ausschließlich diesen Snapshot. HTML verwendet
UTF-8, semantische Tabellen, Druck-CSS und konsequentes Escaping. Der Golden-
Test fixiert den SHA-256 des vollständigen Referenzdokuments. PDF liefert auch
ohne ausgewählte Tabellen wenigstens ein Metadatenblatt.

## Folgen

- Oberfläche, Drill-down und Exporte verwenden identische Fakten und Summen.
- Alte Vorlagen bleiben lesbar; neue Vorlagen speichern Definitionsversion 3.
- HTML benötigt keine zusätzliche Bibliothek.
- XLSX und Zwischenablage bleiben getrennte, noch offene Ausgabekanäle.
