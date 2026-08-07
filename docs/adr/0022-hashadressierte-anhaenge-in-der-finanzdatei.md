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

## Folgen

- SQLite-Online- und Vor-Migrations-Sicherungen enthalten alle Originalbelege.
- Derselbe Inhalt belegt auch bei mehreren Zielobjekten nur einmal Speicher.
- Ein korrupter oder manipulierter BLOB wird vor der Vorschau erkannt.
- Die Buchungsoberfläche unterstützt Auswahl und Drag-and-drop bereits; die
  Oberflächen für weitere Zieltypen verwenden später dasselbe Repository.
- OCR bleibt getrennt vom unveränderten Original vorgesehen, ist aber noch
  nicht implementiert.
- Sehr große Belegbestände vergrößern die SQLite-Datei; die 50-MiB-Grenze und
  Deduplizierung begrenzen den Effekt, ersetzen aber keine spätere
  Aufbewahrungs- und Exportstrategie.
