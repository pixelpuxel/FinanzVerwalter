# ADR 0030: Betragsausdrücke mit Decimal auswerten

## Status

Angenommen am 07.08.2026.

## Kontext

Bei manuellen Buchungen sollen einfache Rechnungen direkt im Betragsfeld
möglich sein. Eine Auswertung über binäre Gleitkommazahlen könnte jedoch
Centabweichungen erzeugen. Plattformparser akzeptieren außerdem teilweise nur
den gültigen Präfix einer fehlerhaften Eingabe und würden damit beispielsweise
`1..2` stillschweigend als `1` behandeln.

## Entscheidung

FinanzVerwalter verwendet einen kleinen eigenen Parser für deutsche
Decimal-Ausdrücke. Er bildet Operatorrangfolge, Klammern und unäre Vorzeichen
explizit ab, validiert jeden Zahlentoken vollständig und rechnet mit
`NSDecimal`-Operationen. Erst das Endergebnis wird mit Banker's-Rundung in die
Minor-Units der gewählten Währung überführt.

Eingabelänge, Rekursion und Operationszahl sind begrenzt. Division durch null,
ungültige Gruppierung, Überlauf und ein Ergebnis außerhalb von `Int64` werden
vor dem Speichern abgewiesen. Der Einzelwertparser nutzt dieselbe strikte
Zahlenvalidierung, interpretiert aber weiterhin keine Operatoren.

## Folgen

Hauptbetrag, Fremdwährungsbetrag, Splits und manuelle Steuerwerte verhalten
sich konsistent und reproduzierbar. Die Implementierung benötigt keine neue
Abhängigkeit. Erweiterte mathematische Funktionen sind bewusst nicht Teil des
Buchungsfelds; die vier Grundrechenarten decken die Produktspezifikation ab.
