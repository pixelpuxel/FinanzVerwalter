# ADR 0062: CSV-Importprofile sind portabel und datenarm

## Status

Angenommen am 08.08.2026.

## Kontext

CSV-/TSV-Importprofile wurden versioniert in den lokalen Einstellungen
gespeichert. Wiederkehrende Bankformate ließen sich dadurch auf demselben Mac
reproduzieren, aber weder bewusst sichern noch auf einer anderen Installation
verwenden. Ein Export aller Einstellungen wäre unnötig umfangreich und könnte
personenbezogene Zustände offenlegen.

## Entscheidung

FinanzVerwalter tauscht genau ein aktuell sichtbares `CSVImportProfile` in
einer JSON-Datei mit der Endung `.fvimportprofil` aus. Ein Envelope enthält
eine konstante Formatkennung, Formatversion 1 und das schema-versionierte
Profil. Das Profil umfasst ausschließlich Parser- und Feldzuordnungsregeln;
Konten, Buchungen, Pfade und Zugangsdaten sind nicht Teil des Modells.

Der Import begrenzt die Datei vor dem Decoding auf 256 KiB. Die JSON-Wurzel
und das Profil müssen exakt die bekannten Schlüssel enthalten. Format- und
Schemaversion, Name, Revision, Zahlenzeichen, Mappingfelder und
Spaltenindizes werden zusätzlich fachlich validiert. Unbekannte oder
zukünftige Strukturen werden abgewiesen.

Identische Profile sind ein No-op. Bei gleicher UUID oder normalisiert
gleichem Namen wählt die Person ausdrücklich zwischen eindeutigem Ersetzen
und einer Kopie mit neuer UUID, Revision 1 und kollisionsfreiem Namen. Treffen
UUID und Name zwei unterschiedliche Profile, wird Ersetzen abgewiesen, damit
niemals zwei lokale Profile durch eine einzige Bestätigung verschwinden.

## Folgen

- Wiederkehrende CSV-/TSV-Formate sind installationsübergreifend
  reproduzierbar, ohne Finanzdaten zu exportieren.
- Beschädigte, übergroße, unerwartete und zukünftige Dateien verändern die
  lokale Profilbibliothek nicht.
- Konflikte sind sichtbar und verlustfrei lösbar.
- Das Austauschformat ist unabhängig von der SQLite-Schemaversion und
  erfordert keine Datenbankmigration.
