# ADR 0061: Berichtsspalten sind Teil der Query

## Status

Angenommen am 08.08.2026.

## Kontext

Die buchungsbasierte Berichtswerkstatt speicherte Filter, Gruppierung,
Sortierung und Darstellung, zeigte und exportierte Detailzeilen jedoch mit
fest verdrahteten, teilweise voneinander abweichenden Spalten. Eine Vorlage
konnte deshalb das gewünschte Druck- und Exportlayout nicht reproduzieren.

## Entscheidung

`TransactionReportQuery.detailColumns` speichert optional eine geordnete
Auswahl stabil codierter `TransactionReportDetailColumn`-Werte. `nil`, eine
leere Auswahl und eine nach Deduplizierung leere Auswahl bedeuten den
bewährten Standardsatz aus Datum, Konto, Empfänger, Verwendungszweck,
Kategorie, Status und Betrag. Dadurch bleiben alte Query-JSONs und Vorlagen
verlustfrei lesbar.

Die Engine normalisiert die Auswahl einmalig und übernimmt sie in
`TransactionReportPresentation`. Tabelle, CSV, PDF, HTML, XLSX und
Zwischenablage lesen ausschließlich diese Snapshot-Auswahl. Beträge bleiben
in XLSX numerisch; alle übrigen Werte werden über eine gemeinsame fachliche
Textabbildung erzeugt. Vorlagen mit Spaltenauswahl verwenden
Definitionsversion 5. Es ist keine Datenbankschemamigration erforderlich.

## Folgen

- Bildschirm und Ausgaben zeigen dieselben Detailfelder in derselben Folge.
- Memo, vollständige Kategorie, Klasse/Tags, Kennzeichen, Währung und
  Splitstatus können gezielt ein- oder ausgeblendet werden.
- Mindestens eine Spalte bleibt in der Oberfläche aktiv.
- Golden-Tests müssen eine bewusste Spaltenänderung als Layoutänderung
  erkennen; ältere Vorlagen erhalten ohne Migration den Standardsatz.
