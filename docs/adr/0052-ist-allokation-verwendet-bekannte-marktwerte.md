# ADR 0052: Ist-Allokation verwendet bekannte Marktwerte je Währung

## Status

Angenommen am 08.08.2026.

## Kontext

Wertpapiere können prozentual auf mehrere Vermögensklassen verteilt sein.
Gleichzeitig können Kurse fehlen und Positionen unterschiedliche Währungen
besitzen. Eine scheinbare Gesamttorte über Nullwerte oder gemischte Währungen
wäre fachlich falsch.

## Entscheidung

Kostenbasis und vorhandener Marktwert jeder Position werden nach der
gespeicherten Basispunktmischung mit Dezimalarithmetik verteilt. Ein
deterministischer Rest auf der letzten stabil sortierten Klasse garantiert,
dass die Teilbeträge centgenau wieder die Position ergeben. Nur vollständige
10.000-Basispunkt-Zuordnungen mit existierenden Klassen werden verwendet;
andere Positionen erscheinen vollständig als `Nicht zugeordnet`.

Der Ist-Anteil einer Klasse ist ihr bekannter Marktwert geteilt durch den
bekannten Gesamtmarktwert derselben Währung. Fehlende Kurse werden gezählt,
bleiben aus dem Nenner heraus und dürfen keinen Nullmarktwert vortäuschen.
Alle Zuordnungen werden beim Datei-Reload gemeinsam geladen, damit die
reaktive Berichtsansicht keine Datenbankabfragen pro Wertpapier auslöst.

## Folgen

- Klassen- und Positionssummen bleiben ohne Rundungsdrift identisch.
- Währungen werden nie unbemerkt addiert.
- Unvollständige Bewertungen und Zuordnungen bleiben sichtbar.
- CSV, PDF, Druck, Diagramm und Tabelle beruhen auf demselben Snapshot.
- Zielallokation, Benchmark und historische Performance bleiben getrennte,
  noch offene Funktionen.
