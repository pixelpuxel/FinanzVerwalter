# ADR 0058: Gruppenabruf wählt keine Fremdkonten

## Status

Angenommen am 08.08.2026.

## Kontext

Die Kontenübersicht konnte einen Banking-Abruf bisher nur aus einer einzelnen
Kontozeile starten. Der Master-Prompt verlangt zusätzlich einen gruppenweisen
Umsatzabruf. Eine Banking-Verbindung kann jedoch auch Zuordnungen zu Konten
anderer Gruppen enthalten. Das bisherige Initialisieren mit allen aktiven
Zuordnungen wäre deshalb für einen Gruppenstart fachlich falsch.

## Entscheidung

Konto- und Gruppenstarts verwenden einen typisierten `BankingLaunchScope`.
Der reine `BankingLaunchSelectionResolver` betrachtet nur aktive Verbindungen
und aktive Zuordnungen zu den angeforderten lokalen Konten. Er wählt die
Verbindung mit der größten Zahl verschiedener Treffer; bei Gleichstand
entscheidet die Verbindungs-UUID deterministisch. Die temporäre Abrufauswahl
enthält ausschließlich die externen IDs dieser Treffer.

Ohne Treffer bleibt die Auswahl leer. Die Oberfläche zeigt Anzahl der
angeforderten, ausgewählten und nicht zugeordneten Konten. In der
Zuordnungszeile steuert die erste Checkbox nur die aktuelle Abrufauswahl; ein
getrennter Schalter `Aktiv` persistiert den Mappingstatus.

## Folgen

- Ein Gruppenabruf kann nicht unbemerkt Konten einer anderen Gruppe laden.
- Teilweise eingerichtete Gruppen bleiben nutzbar und weisen sichtbar auf
  fehlende Zuordnungen hin.
- Verbindungen werden noch nicht in einem einzigen Abruf gemischt. Bei einer
  Gruppe über mehrere Verbindungen wird zunächst die Verbindung mit der
  größten Abdeckung gewählt; weitere Verbindungen können anschließend
  bewusst separat abgerufen werden.
