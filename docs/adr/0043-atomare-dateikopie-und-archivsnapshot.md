# ADR 0043: Atomare Dateikopie und schreibgeschützter Archivsnapshot

## Status

Angenommen am 08.08.2026.

## Kontext

Eine laufende WAL-Datenbank darf nicht mit einer gewöhnlichen Dateikopie
dupliziert werden. Eine Kopie soll weiterbearbeitbar sein; ein Archiv soll den
festgehaltenen Stand dagegen nicht versehentlich als normale Arbeitsdatei
öffnen. Teilgeschriebene oder still überschriebene Ziele sind unzulässig.

## Entscheidung

Beide Operationen verwenden SQLite Online Backup in eine zufällig benannte
Staging-Datei desselben Zielordners. Nach `integrity_check`, eigenständigem
Journalabschluss, Dateirechten sowie einer streamenden Größen- und
SHA-256-Prüfung wird sie atomar verschoben und am endgültigen Ziel erneut
geprüft.

Eine Arbeitskopie trägt `.qdata` und Modus 0600. Ein Archiv trägt
`.qarchive` und Modus 0400. Der normale Öffnen-Befehl akzeptiert weiterhin nur
`.qdata`. Ziele müssen fehlen; die aktive Datei und symbolische Zielordner
sind ausgeschlossen.

Schließen ist eine getrennte Operation: Nach zwingender Online-Sicherung wird
die Verbindung beendet und der komplette veröffentlichte Anwendungszustand
geleert. Öffnen oder Neuanlegen kann anschließend eine neue aktive Repository-
Instanz setzen.

## Folgen

- Kopien und Archive sind konsistente, unmittelbar prüfbare SQLite-Snapshots.
- Ein Abbruch vor der atomaren Verschiebung hinterlässt kein sichtbares Ziel.
- Archiv-Schreibschutz schützt vor Versehen, ist aber keine kryptografische
  Unveränderlichkeit und kann vom Dateieigentümer bewusst aufgehoben werden.
