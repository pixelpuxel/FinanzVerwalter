# ADR 0060: Buchungskennzeichen sind persistente Fachdaten

## Status

Angenommen am 08.08.2026.

## Entscheidung

Buchungskennzeichen werden nicht als flüchtige Oberflächenmarkierung, sondern
als optionales Feld der Buchung gespeichert. Zulässig sind genau sechs stabile
Farbwerte. Schema 40 speichert „ohne Kennzeichen“ als Leerstring, schützt die
Domäne mit einer CHECK-Constraint und indiziert nur markierte Buchungen.

Das Feld gehört zum vollständigen Buchungszustand. Es wird deshalb von
Vorlagen, Undo, Sicherungen und dem offenen Gesamtdatenarchiv erhalten und ist
in Suche, Sortierung, Filter, Editor, Massenänderung sowie konfigurierbaren
Kontenblattausgaben verfügbar.

Die zentrale Berichtswerkstatt behandelt Kennzeichen ebenfalls als
kombinierbaren Queryfilter. Eine fehlende Auswahl bedeutet aus
Rückwärtskompatibilität alle Farben einschließlich unmarkierter Buchungen;
eine vorhandene Auswahl speichert Farben und die Einbeziehung unmarkierter
Buchungen getrennt. Sämtliche Exporte verwenden denselben gefilterten
Snapshot.

## Folgen

Schema 39 wird additiv und ohne fachliche Änderung migriert. Unbekannte
Farbwerte können nicht in die Datenbank gelangen. Eine Massenänderung ist
atomar, auditiert und rücknehmbar; ein Darstellungswechsel kann fachliche
Kennzeichen nicht versehentlich verlieren.
