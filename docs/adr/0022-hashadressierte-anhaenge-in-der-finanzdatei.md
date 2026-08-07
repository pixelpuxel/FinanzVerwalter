# ADR 0022: Hashadressierte Anhänge in der Finanzdatei

## Status

Akzeptiert am 07.08.2026.

## Kontext

Belege müssen lokal, dedupliziert, sicher überprüfbar und gemeinsam mit den
Finanzdaten sicherbar sein. Ein separater Dateibaum würde atomare Änderungen,
vollständige Backups und die Wiederherstellung nach einem Absturz erschweren.
Ein Öffnen direkt aus einer frei gewählten Quelldatei würde außerdem weder den
gespeicherten Inhalt noch dessen Integrität belegen.

## Entscheidung

Schema 32 führt einen zweistufigen Attachment Store ein. `attachment_blobs`
speichert jeden Originalinhalt genau einmal unter seinem SHA-256-Hash;
`attachment_links` verknüpft ihn polymorph mit Konto, Buchung, Vertrag,
Wertpapier oder Inventargegenstand und bewahrt benutzersichtbare Metadaten.
Beide Tabellen und die Original-BLOBs liegen in derselben SQLite-Finanzdatei.

Importe sind auf explizit erlaubte nicht ausführbare Typen und 50 MiB begrenzt.
Regulärdatei, Symlinkstatus, Dateiname, Endung, Magic Bytes beziehungsweise
UTF-8 und ein injizierbarer Scan-Hook werden vor dem atomaren Commit geprüft.
Vor einer bestätigten externen Vorschau werden Größe und SHA-256 erneut
verifiziert; die temporäre Datei erhält Rechte 0600 in einem Verzeichnis 0700.
Ein offener Export prüft denselben gespeicherten BLOB, schreibt zunächst in
eine neue 0600-Staging-Datei im Zielordner und verschiebt beziehungsweise
ersetzt sie erst abschließend. Bestehende Dateien werden nur nach der
Bestätigung des System-Speicherdialogs ersetzt; Symlinks, Pakete, Verzeichnisse,
abweichende Endungen und die Finanzdatei selbst bleiben gesperrt. Größe und
SHA-256 des fertigen Ziels werden erneut geprüft und der Export auditiert.

## Folgen

- SQLite-Online- und Vor-Migrations-Sicherungen enthalten alle Originalbelege.
- Derselbe Inhalt belegt auch bei mehreren Zielobjekten nur einmal Speicher.
- Ein korrupter oder manipulierter BLOB wird vor der Vorschau erkannt.
- Eine gemeinsame Oberfläche unterstützt Auswahl und Drag-and-drop bei
  Buchungen, Konten, Verträgen, Wertpapieren und Inventargegenständen.
- Dieselbe Oberfläche exportiert Originalbelege verifiziert und ohne
  stilles Überschreiben an frei gewählte lokale Ziele.
- OCR bleibt getrennt vom unveränderten Original vorgesehen, ist aber noch
  nicht implementiert.
- Sehr große Belegbestände vergrößern die SQLite-Datei; die 50-MiB-Grenze und
  Deduplizierung begrenzen den Effekt, ersetzen aber keine spätere
  Aufbewahrungs- und Exportstrategie.
