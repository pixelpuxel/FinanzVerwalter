# ADR 0050: Fachauswertungsfenster typisiert reintegrieren

## Status

Angenommen am 08.08.2026.

## Kontext

Ein ausgelagerter Fachbericht hält nach weiteren Filteränderungen einen
anderen Zustand als sein ursprünglicher Öffnungspayload. Beim Rückweg darf
weder dieser neue Zustand verloren gehen noch ein typfremder Bericht geöffnet
werden. Ein alter Launch darf außerdem bei späteren manuellen Aufrufen nicht
erneut erscheinen.

## Entscheidung

`SpecializedReportLaunchPayload` bildet alle sieben Berichtstypen als
codierbare, typisierte Enum-Fälle ab. Jeder Fall bestimmt seinen
`SpecializedReportKind`; dadurch können Typ und Payload nicht auseinander
laufen. `SpecializedReportLaunchRequest` ergänzt eine bei jeder Übergabe
frische UUID.

Das Außenfenster erzeugt den passenden Payload direkt aus der aktuellen
View-Query, sendet ihn über einen eigenen Navigationskanal, schließt sich und
aktiviert das Hauptfenster. `RootView` rekonstruiert `ReportsView` anhand der
Launch-ID. Diese öffnet genau einen Fachdialog und verbraucht den Payload nach
dessen Schließen. Auch der Root-Zwischenspeicher wird im nächsten Main-Runloop
geleert, damit eine spätere View-Rekonstruktion den Launch nicht wiederholt.

## Folgen

- Alle bearbeiteten Filter und die Budget-ID bleiben auf dem Rückweg erhalten.
- Typfremde Kombinationen sind im Launch-Modell nicht darstellbar.
- Identische Queries können dank frischer UUID erneut übergeben werden.
- Manuelle spätere Berichtsaufrufe beginnen wieder mit Standardwerten.
- Fremddatei- und beschädigte Außenfenster bleiben von der Aktion ausgeschlossen.
