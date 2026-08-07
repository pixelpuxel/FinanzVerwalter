# ADR 0026: Folgetermine werden als Revision derselben Serie geändert

## Status

Angenommen am 07.08.2026.

## Kontext

Eine Änderung „dieser und aller folgenden Instanzen“ könnte die alte Serie
beenden und eine neue Serie mit neuer ID anlegen. Bereits materialisierte
erwartete Buchungen tragen jedoch die Herkunftskennung der alten Serie. Eine
neue ID würde ihre Deduplizierung verlieren und könnte dieselben fachlichen
Fälligkeiten ein zweites Mal in der Prognose erzeugen.

## Entscheidung

Ab SQLite-Migration 34 speichert
`scheduled_transaction_revisions` versionierte Änderungspunkte innerhalb
derselben logischen Serie. Der Schlüssel besteht aus Serien-ID und
ursprünglicher Fälligkeit. Eine Revision überschreibt ab dort wirksames
Datum, Empfänger, Verwendungszweck, Kategorie und Betrag. Die vorhandene
Frequenz wird vom neuen Datum aus fortgesetzt. Jede wirksame Folgeinstanz
behält positionsgleich die Herkunftskennung ihrer kanonischen ursprünglichen
Fälligkeit. Spätere Revisionen lösen den Verlauf erneut ab;
Einzelinstanzausnahmen werden zuletzt angewendet.

Eine Einzelausnahme genau am neuen Änderungspunkt wird beim Speichern der
Revision atomar ersetzt und gesondert auditiert. Löschen eines
Änderungspunkts stellt ab dort den vorherigen Revisions- oder Basisverlauf
wieder her.

## Folgen

Auch verschobene Folgen bleiben über Neustarts stabil und bereits
materialisierte Buchungen werden weiterhin erkannt. Serienänderungen sind
sichtbar, editierbar und einzeln rücksetzbar. Ein globaler Frequenzwechsel
für die komplette Serie bleibt weiterhin im Serieneditor; diese Entscheidung
ändert die Frequenz ab einem Änderungspunkt bewusst nicht.
