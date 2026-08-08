# ADR 0017: Eigenständige rotierte Autosicherungen

## Status

Angenommen am 07.08.2026.

## Kontext

Die vorhandene manuelle SQLite-Online-Sicherung und der validierte Restore
schützten vor einem direkten Austausch der laufenden Finanzdatei. Es fehlten
aber automatische Sicherungen, eine Aufbewahrungsrichtlinie und eine
garantierte Vorabkopie vor Schema-Migrationen. Außerdem kann eine SQLite-Datei
im WAL-Modus nur dann als einzelne Datei transportiert werden, wenn alle
Seiten vor der Freigabe in die Hauptdatei checkpointed sind.

## Entscheidung

`AutomaticBackupManager` erstellt im Unterordner `Sicherungen` ausschließlich
vollständige `.qbackup`-Dateien. Standardmäßig wird beim Start und Beenden
geprüft, ob seit der neuesten Sicherung sowohl der Mindestabstand von 24
Stunden abgelaufen als auch die Finanzdatei oder eine ihrer WAL-Seitendateien
geändert wurde. Die Vorgaben sind in den Einstellungen änderbar; eine
erzwungene geprüfte Sicherung ist jederzeit möglich.

Jede Sicherung entsteht zunächst unter einem einmaligen versteckten Namen.
Der SQLite-Backup-Writer beendet die Online-Kopie, checkpointed WAL, wechselt
das Ziel auf `journal_mode=DELETE`, schließt alle Statements und die
Zieldatenbank und entfernt leere Seitendateien. Erst nach einer
`immutable=1`-Integritätsprüfung wird die Datei atomar auf ihren endgültigen
Namen verschoben. Ein vorhandenes Ziel oder die Quelldatei selbst darf nie
überschrieben werden.

Die Rotation behält standardmäßig höchstens 14 Sicherungen und höchstens 90
Tage alte Dateien; beide Grenzen sind konfigurierbar und gelten nur für vom
Programm eindeutig benannte Autosicherungen. Vor jeder Migration eines
bekannten älteren Schemas wird unabhängig von der zeitlichen Richtlinie eine
eigene geprüfte Sicherung angelegt. Ein Schema neuer als die vom Programm
unterstützte Version wird ohne Migration oder Mutation abgewiesen.

## Folgen

- Die erste produktive Autosicherung ist eine allein lesbare Datei ohne
  Abhängigkeit von `-wal` oder `-shm`.
- Mengen- und Altersrotation löschen bewusst nur eindeutig benannte
  Autosicherungen; manuelle und Vor-Migrations-Sicherungen bleiben erhalten.
- Verschlüsselung, mehrere frei wählbare Finanzdateien, Reparaturkopien und
  ein Installer-weites Update-Rollback bleiben getrennte Folgearbeiten.
- Automatische Sicherungen schützen vor Dateiverlust, ersetzen aber keine
  externe oder räumlich getrennte Sicherungsstrategie.
