# ADR 0047: Unabhängige, finanzdateigebundene Berichtsfenster

## Status

Angenommen am 08.08.2026.

## Kontext

Eine Desktop-Finanzverwaltung muss mehrere Auswertungen parallel zeigen
können. Ein einziges Hauptfenster zwingt Nutzer sonst, Filter und Drill-down
beim Vergleich wiederholt umzubauen. Gleichzeitig darf ein offenes
Berichtsfenster nach dem Wechsel der aktiven Finanzdatei seine alte Query nicht
still auf einen anderen Datenbestand anwenden.

## Entscheidung

Die Berichtswerkstatt kann ihre vollständige aktuelle
`TransactionReportQuery` zusammen mit Titel, kanonischem Finanzdateipfad und
einer frischen UUID in einen codierbaren `ReportWindowRequest` verpacken. Ein
typisiertes SwiftUI-`WindowGroup` öffnet für jede UUID ein eigenes Fenster und
dekodiert dort die Query. Filter, Gruppierung, Darstellung, Drill-down,
Vorlagen und sämtliche Exporte arbeiten anschließend unabhängig im jeweiligen
Fenster auf dem gemeinsam publizierten Datenstand.

Vor jeder Darstellung vergleicht das Fenster den gespeicherten kanonischen
Pfad mit der aktiven Finanzdatei. Bei Abweichung oder geschlossener Datei zeigt
es ausschließlich einen Sperrhinweis. Eine unlesbare Query wird ebenfalls als
Fehlerzustand dargestellt. Fensteridentität und Query sind codierbar, damit
macOS die Fensterzustände sicher verwalten kann.

## Folgen

- Beliebig viele buchungsbasierte Berichte können parallel verglichen werden.
- Zwei gleiche Queries erzeugen auf Wunsch trotzdem getrennte Fenster.
- Ein Finanzdateiwechsel vermischt keine Berichtsdaten.
- Spezialisierte Berichtsansichten benötigen eigene typisierte Fensterpayloads
  und bleiben als gesonderter Ausbau offen.
