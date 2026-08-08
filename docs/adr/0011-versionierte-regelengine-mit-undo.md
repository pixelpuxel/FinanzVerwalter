# ADR 0011: Versionierte Regel-Engine mit Auswahl und sicherem Undo

## Status

Akzeptiert am 31.07.2026.

## Kontext

Die bisherige Kategorisierungsregel bestand aus zwei optionalen
`enthält`-Feldern, Betragsgrenzen und genau einer Kategorieaktion. Sie konnte
weder AND/OR-Gruppen noch Regex, Bankidentitäten, mehrere Aktionen,
Konflikte, eine buchungsweise Auswahl oder ein belastbares Undo abbilden.

## Entscheidung

Migration 20 ergänzt jede bestehende Regel um eine versionierte,
deterministisch als JSON codierte Definition. Die Definition besteht aus
rekursiven AND/OR-Ausdrücken und typisierten Bedingungen. Unterstützt werden
Empfänger/Auftraggeber, Zweck, IBAN, BIC, Betrag, Vorzeichen, Konto,
Buchungstext, Referenz, Mandatsreferenz, Gläubiger-ID, End-to-End-ID,
Zeitraum, Notiz, Status und Herkunft. Operatoren sind gleich, enthält,
beginnt/endet mit, Regex, Bereich sowie leer/nicht leer.

Typisierte Aktionen setzen Kategorie, normalisieren Empfänger, setzen oder
kopieren Notizen, ergänzen Tags, ersetzen Zwecktext oder erzeugen einen
centgenauen Einzeilen-Split. Betrag, Konto, Abgleichstatus und
Transferstruktur werden nicht verändert. Abgeglichene, stornierte und
Transferbuchungen sind ausgeschlossen.

Vor der Anwendung entsteht eine unveränderliche Vorher/Nachher-Vorschau.
Der Nutzer wählt die tatsächlich zu ändernden Buchungen aus. Die Engine
prüft die Auswahl unmittelbar vor dem atomaren Commit erneut.

In derselben SQLite-Transaktion wird pro geänderter Buchung ein vollständiger
Vorher-Snapshot und der Fingerabdruck des Nachher-Zustands gespeichert. Das
Undo ist einmalig und vollständig: Fehlt eine Buchung oder wurde sie
zwischenzeitlich geändert, wird keine einzige Buchung zurückgesetzt.

Alte Regeln werden beim Lesen in eine stabile typisierte Definition
projiziert. Erst beim nächsten Speichern wird die neue JSON-Definition
persistiert; bestehendes Verhalten und IDs bleiben erhalten.

## Folgen

- Regelreihenfolge und Priorität bleiben sichtbar und deterministisch.
- Potenziell widersprüchliche Aktionen mehrerer Regeln werden vorab
  buchungs- und feldbezogen angezeigt.
- Ungültige Regex- und Betragsbedingungen werden beim Speichern abgelehnt.
- Ein Kontextmenübefehl erzeugt aus einer einfach kategorisierten Buchung
  eine noch nicht angewandte kontospezifische Regel.
- Künftige Banking-Adapter können dieselbe Engine nach dem sicheren
  Import-Matching verwenden.
