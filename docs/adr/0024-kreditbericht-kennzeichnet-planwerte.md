# ADR 0024: Kreditbericht kennzeichnet Planwerte

## Status

Angenommen am 07.08.2026.

## Kontext

FinanzVerwalter kann aus Darlehensstammdaten, versionierten Zinssätzen,
Gebühren und Sondertilgungen einen Tilgungsplan berechnen. Tatsächliche
Kontobuchungen werden derzeit noch nicht mit dessen Raten verknüpft. Ein
Bericht darf deshalb geplante Zahlungen nicht als Ist-Zahlungen darstellen.

## Entscheidung

Der Kredit-, Zins- und Tilgungsbericht besitzt eine eigene unveränderliche
Snapshot-Engine. Er filtert Zeitraum, Darlehen, Währung und Aktivstatus,
bewahrt stabile Planzeilen-IDs für den Drill-down und bildet Summen nur je
Währung. Bildschirm, CSV, PDF und Systemdruck stammen aus demselben Snapshot
und tragen sichtbar den Hinweis `Planwerte – kein Ist-Zahlungsabgleich`.

## Folgen

Der Bericht ist bereits für Planung und Restschuldverläufe nutzbar, ohne eine
nicht vorhandene Ist-Verknüpfung vorzutäuschen. Automatische Ratensplits,
Zahlungs-Matching und Szenarien bleiben getrennte, ausdrücklich offene
Funktionen.
