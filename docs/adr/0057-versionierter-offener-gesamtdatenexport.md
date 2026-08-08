# ADR 0057: Versionierter offener Gesamtdatenexport

## Status

Angenommen am 08.08.2026.

## Kontext

Eine SQLite-Sicherung ist vollständig, aber ohne die Anwendung nur mit
Schemawissen zugänglich. Einzelne CSV-, QIF- oder Berichtsexporte bilden
dagegen nicht alle Beziehungen, Einstellungen und Anhänge ab. Ein wirklich
portabler Gesamtexport muss offen lesbar sein, darf jedoch keine lokalen
Zugriffstoken oder gerätegebundenen Dateiberechtigungen verbreiten.

## Entscheidung

FinanzVerwalter exportiert ein neues `.finanzarchiv`-Verzeichnis mit der
Formatkennung `de.pixelpuxel.finanzverwalter.open-data` und Version 1. Ein
konsistenter SQLite-Online-Snapshot wird unveränderlich gelesen. Jede
Anwendungstabelle erscheint vollständig, stabil nach Primärschlüssel sortiert,
in `data.json` und einer eigenen RFC-4180-CSV. `schema.json` beschreibt
Spalten und Schlüssel. Anhangs-BLOBs werden nach Größen- und Hashprüfung
einmalig als Originaldateien ausgegeben und in den Tabellen referenziert.

Die Einstellungsdatei basiert auf einer festen Whitelist. Lokale/recent
Finanzdateipfade, Security-Scoped Bookmarks und jede Art von Zugangs- oder
Banking-Token sind ausgeschlossen. Das Paket entsteht mit privaten Rechten in
einem versteckten Zwischenordner, enthält ein vollständiges SHA-256-Manifest
und wird erst nach atomarer Freigabe am Ziel erneut vollständig validiert.

## Folgen

- Nutzer können alle fachlichen Daten mit Standardwerkzeugen lesen und in
  andere Systeme migrieren.
- Stabile Schlüssel und Reihenfolgen machen gleiche Exporte vergleichbar.
- Anhänge bleiben verlustfrei erhalten, ohne das JSON unnötig aufzublähen.
- Sicherheitsrelevante lokale Zustände werden bewusst nicht transportiert.
- Das Archiv ist ein Exportvertrag, noch kein Wiederherstellungsformat; ein
  geprüfter Rückimport braucht eine eigene spätere Entscheidung.
