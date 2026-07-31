# ADR 0006: Daueraufträge als idempotente Fälligkeiten

- Status: angenommen
- Datum: 31. Juli 2026

## Kontext

Ein Dauerauftrag ist weder nur eine Prognosebuchung noch bereits eine
übermittelte Zahlung. Änderungen an seiner Vorlage dürfen vergangene
Instanzen nicht verändern. Wiederholte Klicks, Prozessabbrüche oder ein
unklarer UI-Zustand dürfen keinen zweiten Zahlungsauftrag für dieselbe
Fälligkeit erzeugen.

## Entscheidung

Migration 14 speichert `standing_orders` getrennt von `payment_orders`.
Jede verarbeitete Fälligkeit erhält in `standing_order_runs` genau eine
Zeile, eindeutig durch Dauerauftrags-ID und kalendarisches Fälligkeitsdatum.

Die Materialisierung schreibt innerhalb einer SQLite-Transaktion:

1. einen Terminüberweisungsentwurf mit dem Idempotenzschlüssel
   `standing:<UUID>:<yyyy-MM-dd>`,
2. eine terminale Historienzeile,
3. den nächsten Termin beziehungsweise den Endstatus der Vorlage.

Ein erneuter Aufruf derselben materialisierten Fälligkeit liefert den
vorhandenen Entwurf. Eine übersprungene Fälligkeit bleibt übersprungen.
Pausieren ist reversibel, Beenden ist terminal. Vorlagen dürfen nicht hinter
die letzte verarbeitete Fälligkeit zurückgesetzt werden.

Wochenenden werden wahlweise nicht, zum vorherigen oder zum nächsten
Wochentag verschoben. Gesetzliche und regionale Feiertage bleiben offen,
bis ein versionierter, getesteter Kalender eingeführt wird.

## Folgen

- Alte Entwürfe bleiben auch nach Vorlagenänderungen unverändert.
- Doppelentwürfe werden durch Datenbank- und Domäneninvarianten verhindert.
- Das Modell eignet sich später als Quelle für einen bankabhängigen
  FinTS-Dauerauftragsadapter, behauptet derzeit aber ausschließlich lokale
  Simulation.
- Die Tabellen sind additiv; eine Schema-13-Rollbackkopie kann nur verwendet
  werden, solange keine Dauerauftragsdaten erhalten werden müssen.
