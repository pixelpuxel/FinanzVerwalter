# ADR 0035: Betrag oder Soll/Haben im Kontoblatt

## Status

Angenommen am 07.08.2026.

## Kontext

Der Master-Prompt verlangt im Kontoblatt wahlweise eine einzelne Betragsspalte
oder die klassische getrennte Soll-/Haben-Darstellung. Die gespeicherte
Buchung muss dabei ihr Vorzeichen behalten, und sämtliche sichtmengengleichen
Ausgaben dürfen nicht von der Tabelle abweichen.

## Entscheidung

`RegisterAmountColumnMode` ist eine lokale, persistente Ansichtspräferenz und
ein optionales Feld benannter Einzel- und Sammelkontoblattansichten.
`RegisterColumnLayout` ersetzt die konfigurierbare logische Spalte `Betrag` im
getrennten Modus ausschließlich in der fertigen Darstellung durch die
virtuellen Spalten `Soll` und `Haben`. Diese virtuellen Spalten werden nicht in
der unabhängigen Spaltenauswahl gespeichert.

`RegisterAmountPresentation` liefert für negative Werte den sicheren positiven
Absolutbetrag nur für Soll, für positive Werte denselben Betrag nur für Haben
und für Null beide Male keinen Wert. Der signierte `amountMinor` bleibt
unverändert. Einzel-, Zweit- und Sammelkontoblatt, native Spaltensortierung,
Accessibility und `RegisterPrintSnapshot` verwenden dieselbe Spaltenfolge.
Alte Ansichten ohne Modusfeld fallen auf `Betrag` zurück.

## Folgen

Die Darstellung lässt sich ohne Datenmutation und ohne Verlust des Vorzeichens
umschalten. PDF, Systemdruck und CSV zeigen genau die gewählte Variante.
Zusätzliche virtuelle Spalten verunreinigen weder alte Spalteneinstellungen
noch deren Migration.
