# ADR 0045: Pfadbasierte Suche in der Kategoriehierarchie

## Status

Angenommen am 08.08.2026.

## Kontext

Gleichnamige Unterkategorien wie `Grundsteuer` sind ohne ihren vollständigen
Pfad nicht eindeutig. Eine flache Namenssuche verliert außerdem den Kontext
eines Treffers, wenn dessen Oberkategorien nicht selbst zum Suchtext passen.
Inaktive Kategorien dürfen aktive Nachfolger nicht aus dem Baum abschneiden.

## Entscheidung

Die Kategorieverwaltung bildet eine normalisierte Suchfläche aus vollständigem
Pfad, Beschreibung, Kategorieart und beiden Steuerzuordnungen. Leerraumgetrennte
Suchwörter werden mit UND verknüpft; Groß-/Kleinschreibung, Diakritika und
Zeichenbreite werden ignoriert. Für jeden Treffer werden alle Ahnen in die
sichtbare ID-Menge aufgenommen. Der Inaktiv-Schalter filtert inaktive Treffer,
erhält aber inaktive Ahnen, die zum Darstellen eines aktiven Treffers nötig
sind. Während einer Suche erscheint der vollständige Pfad als kompakte zweite
Zeile; ohne Treffer zeigt die Liste einen erklärenden Leerzustand.

## Folgen

- Gleichnamige Unterkategorien bleiben eindeutig auffindbar.
- Der sichtbare Baum ist auch bei tiefen Treffern zusammenhängend.
- Deutsche Namen sind auch ohne eingegebene Umlaute auffindbar.
- Die Filterlogik ist unabhängig von SwiftUI deterministisch testbar.
