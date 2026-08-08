# ADR 0038: Auditierbare Korrektur von Zahlungsentwürfen

## Status

Angenommen am 07.08.2026.

## Kontext

Ein lokaler Überweisungsentwurf muss vor der bewussten Initiierung korrigierbar
sein. Nach Beginn einer Übermittlung bildet der Auftrag dagegen einen
unveränderlichen Schnappschuss für Bestätigung, Idempotenz, Statusimport und
Audit. Löschen würde außerdem verschleiern, dass ein Auftrag bewusst
abgebrochen wurde.

## Entscheidung

Nur ein einzelner Auftrag im Zustand `draft`, der keinem Sammler angehört,
darf bearbeitet werden. Das Repository prüft innerhalb der Mutation erneut
Auftraggeberkonto, EUR-Währung, SEPA-Felder, Empfängerakte und Bankverbindung.
Die Anwendung berechnet den Idempotenzschlüssel aus den kanonischen geänderten
Feldern neu; eine Kollision mit einem anderen Auftrag ist ein harter Fehler.
UUID, Erstellungszeit und Status bleiben erhalten, die Version steigt und ein
`update_draft`-Auditereignis beschreibt Typ-, Betrags- und Terminänderung.

Ein freier Entwurf und ein noch nicht eingereichter Auftrag im Zustand
`awaiting_user` können nach eigener Bestätigung nach `cancelled` wechseln.
Der Datensatz wird nicht gelöscht. Sammlermitglieder, initialisierte,
übermittelte und terminale Einzelaufträge bleiben unveränderlich.

## Folgen

Fehleingaben können vor der Übermittlung sicher korrigiert werden, ohne
Duplikat- oder Stammdatenkontrollen zu umgehen. Abbruch bleibt historisch
sichtbar und erzeugt keine Buchung. Eine spätere Fachanforderung an die
Korrektur von Lastschriftentwürfen benötigt wegen des eingefrorenen
Mandats-/Gläubigerschnappschusses eine eigene Entscheidung.
