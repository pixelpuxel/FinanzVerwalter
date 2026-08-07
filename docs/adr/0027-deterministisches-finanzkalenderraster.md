# ADR 0027: Deterministisches Finanzkalenderraster

## Status

Akzeptiert am 07.08.2026.

## Kontext

Der Finanzkalender muss reale Buchungen und virtuelle regelmäßige Vorgänge in
Monat, Woche und Liste verständlich zusammenführen. Plattformabhängige
Wochenanfänge oder nicht aufgefüllte Monatsränder führen besonders an
Jahresgrenzen zu uneindeutigen Zellen. Gleichnamige Unterkategorien dürfen in
Filtern nicht ihre Hierarchie verlieren.

## Entscheidung

Monats- und Wochenraster werden aus einer reinen, testbaren Layoutfunktion
erzeugt. Sie setzt Montag als Wochenanfang und vier Mindesttage in der ersten
Woche. Eine Woche enthält sieben Tage. Ein Monat reicht vom Montag der ersten
berührten Woche bis zum Sonntag der letzten berührten Woche; Randtage werden
gekennzeichnet.

Die Oberfläche vereinigt für die Anzeige gefilterte reale Buchungen mit den
bereits deduplizierten virtuellen Serienterminen. `expected`, `pending`, die
drei gebuchten Zustände und `cancelled` werden stabil klassifiziert; virtuelle
Termine bilden eine eigene Klasse. Konto-, Kategorie- und Klassenfilter sind
kombinierbar. Hierarchiefilter schließen Nachfahren ein und prüfen auch
Splitzeilen; Auswahllisten zeigen stets den vollständigen Pfad.

## Folgen

Schaltmonate und Wochen über Jahresgrenzen sind ohne UI deterministisch
testbar. Der Kalender verändert keine Buchungs- oder Prognosedaten. Reale und
virtuelle Vorgänge können visuell unterschieden werden, ohne die bestehende
Serienbearbeitung der Liste zu verlieren. Direktes Drag-and-drop und
Was-wäre-wenn-Szenarien bleiben getrennte Erweiterungen.
