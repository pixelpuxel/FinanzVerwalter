# ADR 0044: Read-only Wiederherstellungsvorschau vor Dateiaustausch

## Status

Angenommen am 08.08.2026.

## Kontext

Eine reine Bestätigungsfrage belegt nicht, welche Sicherung ausgewählt wurde
oder ob ihr Schema von der laufenden App verarbeitet werden kann. Eine erst
nach dem Dateiaustausch erkannte Zukunftsversion könnte die aktive Datei
vorübergehend unbenutzbar machen. Die Vorschau darf ihrerseits weder die
Sicherung migrieren noch WAL-/SHM-Dateien erzeugen.

## Entscheidung

Der Dateidialog kopiert die gewählte Sicherung in eine zufällige Tempdatei.
Die Persistenzschicht fordert eine reguläre Datei ohne Symlink, validiert
Finanzdateikopf und Integrität und öffnet sie ausschließlich read-only mit
`immutable=1`. Vor jeder Änderung am aktiven Bestand wird `user_version`
gegen Schema 39 geprüft.

Die Vorschau zeigt Finanzdateiname, Basiswährung, Schema, Konten-, Kategorien-
und Buchungszahl, jüngstes Buchungsdatum, Dateigröße und Dateistand. Erst der
explizite destruktive Standardknopf startet den bestehenden Restore mit
zusätzlicher Sicherheitskopie. Abbruch, Fehler und Abschluss entfernen die
Tempdatei.

## Folgen

- Nutzer sehen den fachlichen Inhalt vor dem Austausch.
- Ein intaktes, aber inkompatibles Zukunftsschema verändert die aktive Datei
  nicht und erzeugt auch keine unnötige Vor-Restore-Sicherung.
- Die Vorschau ist ohne Migration und ohne Seitendateien reproduzierbar.
- Die Tempkopie schützt zugleich vor Änderungen der externen Quelldatei
  zwischen Vorschau und Bestätigung.
