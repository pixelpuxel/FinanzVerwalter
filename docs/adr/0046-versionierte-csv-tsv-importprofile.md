# ADR 0046: Versionierte CSV-/TSV-Importprofile

## Status

Angenommen am 08.08.2026.

## Kontext

Banken und Fremdprogramme liefern Textumsätze mit unterschiedlichen
Kodierungen, Trennzeichen, Datums- und Zahlenformaten sowie frei benannten und
angeordneten Spalten. Eine feste Parserannahme kann Beträge mit falschem
Vorzeichen lesen, Kategorien verwechseln oder fachliche Bankreferenzen
verlieren. Wiederkehrende Exporte derselben Quelle sollen ohne erneute
Konfiguration reproduzierbar bleiben.

## Entscheidung

Vor der normalen Importvorschau steht ein eigener Profilassistent. Ein
`CSVImportProfile` beschreibt schema-versioniert Encoding, Trennzeichen,
Kopfzeile, Datumsformat, Dezimal- und Tausenderzeichen, Betragsmodus und die
Zuordnung sämtlicher unterstützter Zielfelder zu nullbasierten Quellspalten.
Eine deterministische Erkennung liefert nur den Ausgangspunkt; der Nutzer
sieht Rohdaten und kann jede Annahme korrigieren.

Der Parser verarbeitet maskierte Trennzeichen, verdoppelte Anführungszeichen,
CRLF und Zeilenumbrüche in maskierten Feldern. Geld wird dezimal ohne
Binärgleitkomma gelesen. Im Soll-/Haben-Modus ist Soll negativ und Haben
positiv; gleichzeitig belegte Spalten sind ein Zeilenfehler. Kategorien
werden vorrangig über den vollständigen Pfad und nur bei Eindeutigkeit über
den Blattnamen aufgelöst. Strukturelle Fehler brechen die Vorschau ab,
inhaltliche Fehler bleiben mit Quellzeilennummer sichtbar.

Benannte Profile liegen als versioniertes JSON in `UserDefaults` und enthalten
keine Buchungsdaten. Speichern erhöht die Revision desselben Profils; ein
neueres unbekanntes Schema wird abgewiesen. Die erzeugten Buchungen durchlaufen
unverändert das bestehende gestufte Matching und den atomaren Import-Commit.

## Folgen

- Wiederkehrende Bankexporte lassen sich reproduzierbar importieren.
- Der Nutzer bestätigt Format und Semantik, bevor Finanzdaten verändert werden.
- Volle Kategoriepfade verhindern Verwechslungen gleichnamiger Unterkategorien.
- Künftige Profiländerungen benötigen eine explizite Schemamigration.
