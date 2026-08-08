# ADR 0007: Auditierbarer Kontoabgleich mit expliziter Auswahl

## Status

Angenommen am 31.07.2026.

## Kontext

Der bisherige Kontoabgleich verglich den Auszugsendsaldo mit dem gesamten
lokalen Saldo zum Stichtag und setzte anschließend pauschal alle gebuchten
oder bestätigten Buchungen auf `reconciled`. Damit waren weder die tatsächlich
auf einem Auszug enthaltenen Positionen noch Anfangssaldo, markierte Summe,
Differenzbuchung und fachlich sichere Rücknahme rekonstruierbar.

## Entscheidung

Migration 15 erweitert jeden Abgleichssatz um Anfangssaldo, markierte Summe,
optionale Ausgleichsbuchung und Workflowversion. Die neue Tabelle
`reconciliation_items` hält jede ausgewählte Buchung mit Betrag,
vorherigem Status und Ausgleichskennzeichen fest. Migration 16 ergänzt eine
monoton steigende Folge, damit der jüngste Abgleich auch bei identischem
Auszugsdatum und sekundengenau gleichem Zeitstempel eindeutig bestimmt ist.

Ein Abgleich beginnt mit dem Endsaldo des jüngsten aktiven Abgleichs oder,
falls keiner existiert, mit dem Eröffnungssaldo. Nur explizit ausgewählte,
bis zum Auszugsdatum gebuchte oder bestätigte Buchungen werden geschützt.
Eine Differenz verhindert den Abschluss. Der Nutzer kann sie ausschließlich
über einen zweiten, ausdrücklichen Bestätigungsschritt als Buchung mit
Referenz `ABGLEICH` ausgleichen.

Nur der jüngste aktive Abgleich eines Kontos ist rücknehmbar. Ausgewählte
Buchungen erhalten atomar ihren vorherigen Status. Eine Ausgleichsbuchung
wird storniert und nicht gelöscht. Abgleichssatz, Positionen und
Auditereignisse bleiben erhalten. Alte Abgleiche aus früheren Schemata bleiben
lesbar, werden aber mangels rekonstruierbarer Positionsliste nicht
rücknehmbar gemacht.

## Folgen

- Abgleichssumme und Schutzstatus sind auf konkrete Auszugspositionen
  zurückführbar.
- Rücknahme verändert keine ältere Historie und lässt keine Differenzbuchung
  verschwinden.
- Rückdatierte Abgleiche vor dem jüngsten aktiven Auszugsdatum werden
  abgewiesen.
- Der Dialog benötigt eine Mehrfachauswahl und zeigt fünf Beträge permanent:
  Anfangssaldo, markierte Summe, berechneter Saldo, Auszugsendsaldo und
  Differenz.
- Ein Migrations- und ein Domänentest schützen Bestandshistorie,
  Auswahlgrenzen, explizite Differenzbuchung, Reihenfolge und Rücknahme.
