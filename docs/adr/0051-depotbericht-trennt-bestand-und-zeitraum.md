# ADR 0051: Depotbericht trennt aktuellen Bestand und Transaktionszeitraum

## Status

Angenommen am 08.08.2026.

## Kontext

Die Datenbank besitzt aktuelle Depotpositionen und einzelne
Wertpapiertransaktionen, aber noch keine lückenlose historische Kursreihe.
Ein frei gewählter Zeitraum darf deshalb nicht den Eindruck erwecken, der
Bestand oder seine Performance sei rückwirkend bewertet worden.

## Entscheidung

Der Bericht zeigt den Depotbestand stets als aktuelle Momentaufnahme. Der
optionale Zeitraum gilt ausschließlich für die daneben ausgewerteten
Transaktionen. Kostenbasis, letzter Kurs, Marktwert und unrealisiertes Ergebnis
stammen aus den aktuellen Positionen. Verkäufe, Dividenden, Gebühren und
Steuern stammen aus den gespeicherten, zeitraumgefilterten Transaktionen und
werden je Währung getrennt summiert.

Fehlende Kurse bleiben optional. Der Bericht zählt sie und bezeichnet die
Marktwertsumme sichtbar als unvollständig, statt sie mit Null zu bewerten.
CSV, PDF, Druck und Oberfläche verwenden denselben unveränderlichen Snapshot.
Die vollständige Query ist der achte typisierte Fachberichtspayload für
Außenfenster und Reintegration.

## Folgen

- Aktuelle Bestände und tatsächlich gespeicherte Erträge sind nachvollziehbar.
- Verschiedene Währungen werden nicht unbemerkt addiert.
- Der Zeitraum kann keinen historischen Depotstand vortäuschen.
- Historische Bewertung, TWR/IRR, Benchmarks und Allokationsberichte bleiben
  ausdrücklich offen, bis die benötigten Zeitreihen und Bewertungsregeln
  vorhanden sind.
