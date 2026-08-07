# ADR 0024: Kreditbericht kennzeichnet Planwerte

## Status

Angenommen am 07.08.2026. Der fehlende Ist-Abgleich wurde später durch
ADR 0029 abgelöst; die Trennung von Plan- und Ist-Werten bleibt bestehen.

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

Diese Entscheidung verhinderte bis Schema 36, dass eine nicht vorhandene
Ist-Verknüpfung vorgetäuscht wurde. Seit Schema 37 ergänzt ADR 0029 reale,
reversible Ratensplits und weist Plan und Ist weiterhin getrennt aus;
Kredit-Szenarien bleiben offen.
