# ADR 0053: Wertpapiererträge und Gebühren sind lotneutrale Cashflows

## Status

Angenommen am 08.08.2026.

## Kontext

Die Depotberechnung kann Käufe und FIFO-Verkäufe sowie Erträge und Gebühren
auswerten. Erträge und eigenständige Gebühren waren bislang jedoch nicht über
die Oberfläche erfassbar. Würden sie als Stücktransaktion oder künstliche
Kontobuchung modelliert, könnten Bestände verändert oder nicht vorhandene
Verrechnungskonten vorgetäuscht werden.

## Entscheidung

Dividenden- und Zinserträge sowie eigenständige Wertpapiergebühren werden als
lotneutrale Einträge in `security_trades` gespeichert. Stückzahl, Kurs und
realisierter Gewinn sind dabei null. Ein Ertrag besitzt einen positiven
Bruttobetrag und nichtnegative Gebühren und Steuern; Brutto muss mindestens
der Summe der Abzüge entsprechen. Sein berichteter Nettoertrag ist Brutto
minus Gebühren minus Steuern. Eine Gebühr besitzt einen positiven Wert im
Gebührenfeld.

Vor dem atomaren Speichern werden ein offenes Depot und ein aktives
Wertpapier verlangt. Alle Geldwerte verwenden die Wertpapierwährung. Die
Vorgänge erzeugen weder Anschaffungslots noch Lot-Verbräuche und verändern
keine Depotposition. Eine Bank- oder Verrechnungskontobuchung wird nicht
implizit erzeugt.

## Folgen

- Erträge, Gebühren und Steuern sind direkt erfassbar und im Depotbericht
  sowie dessen Exporten sichtbar.
- FIFO-Bestände und Kostenbasis bleiben von Cashflows unberührt.
- Fremdwährungswertpapiere werden nicht fälschlich in EUR geparst.
- Kontosalden bleiben unverändert, bis eine spätere explizite Kopplung an ein
  Verrechnungskonto implementiert wird.
- Wiederanlage, Steuererstattung und Kapitalmaßnahmen bleiben eigene, noch
  offene Vorgangstypen.
