# ADR 0056: Reparaturmodus arbeitet nur auf einer Kopie

## Status

Angenommen am 08.08.2026.

## Kontext

Der Master-Prompt verlangt einen Reparaturmodus ausschließlich auf einer
Kopie. Eine Wartungsaktion an der geöffneten Finanzdatei könnte bei Absturz,
Speichermangel oder bereits inkonsistenten Daten den letzten nutzbaren Stand
verschlechtern. Ein bloß anders benanntes Online-Backup würde dagegen weder
Indizes noch die physische Seitenstruktur neu aufbauen.

## Entscheidung

FinanzVerwalter erzeugt zuerst per SQLite Online Backup eine vollständige,
versteckte Zwischenkopie. Nur in dieser Kopie laufen `REINDEX`, `VACUUM` und
`PRAGMA optimize`. Danach müssen `foreign_key_check` leer und
`integrity_check` erfolgreich sein. Die geschlossene, sidecarfreie Datei wird
unveränderlich erneut validiert, auf `0600` gesetzt, mit SHA-256 und Größe
geprüft und erst anschließend atomar an ein vorher freies `.qdata`-Ziel
verschoben. Hash und Größe werden nach dem Verschieben nochmals verglichen.

Die aktive Datei, ein vorhandenes Ziel, Symlink-Zielordner und Ziele mit
falscher Endung sind ausgeschlossen. Fehler entfernen nur die selbst erzeugte
Zwischenkopie. Die Aktion ersetzt oder öffnet die aktive Finanzdatei nicht.

## Folgen

- Defekte Indizes, unnötige Seiten und fragmentierte Layouts können in einer
  unabhängigen Kopie sicher neu aufgebaut werden.
- Die geöffnete Finanzdatei bleibt auch bei einem Fehlschlag unangetastet und
  weiter verwendbar.
- Die resultierende Kopie ist sofort als eigenständige Finanzdatei öffnbar.
- Der Modus ist keine allgemeine forensische SQLite-Wiederherstellung. Eine
  physisch unlesbare Quelle kann nicht als erfolgreich repariert behauptet
  werden.
