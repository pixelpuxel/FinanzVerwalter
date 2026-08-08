# ADR 0027: Freistellungsaufträge als institutsweiter Jahresrahmen

## Status

Angenommen am 07.08.2026.

## Kontext

Freistellungsaufträge werden bei mehreren Instituten verteilt, gelten dort
aber nicht nur für ausgewählte Einzelkonten. Gesetzliche Höchstbeträge ändern
sich über die Zeit. Bei gemeinsamem Rahmen müssen vorhandene Einzelaufträge
beider Partner mitgerechnet werden. Die vollständige Steuer-ID wäre in der
derzeit unverschlüsselten Finanzdatei unnötig sensibel.

## Entscheidung

- Schema 36 trennt Personen, versionierte gesetzliche Regeln, Aufträge,
  Kontenabdeckung und jährliche Nutzung.
- Gespeichert werden nur die letzten vier Steuer-ID-Ziffern und ein
  Bestätigungsstatus.
- Kontenzuordnungen dokumentieren die Abdeckung, begrenzen einen Auftrag aber
  nicht. Zugeordnete Konten müssen dasselbe Institut tragen.
- Einzelaufträge zählen allein gegen den Einzelrahmen. Existiert ein
  gemeinsamer Rahmen, zählen die Einzelaufträge beider Partner und die
  gemeinsamen Aufträge zusammen gegen den gemeinsamen Höchstbetrag.
- Ein Auftrag kann nur zum Ende eines Kalenderjahres befristet werden; die
  jährliche Nutzung ist eine eigene versionierte Zeile.
- Die Funktion ist lokale Verwaltungshilfe und übermittelt nichts an Banken.

## Folgen

Historische Jahre bleiben reproduzierbar, neue gesetzliche Grenzen können als
zusätzliche Regelzeilen ergänzt werden und Berichte zeigen echte Jahresstände.
Eine elektronische Erteilung oder Änderung bei Instituten sowie rechtliche
oder steuerliche Beratung bleiben ausdrücklich außerhalb des Funktionsumfangs.
