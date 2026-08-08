# ADR 0054: Depotperformance trennt Cashflows und Währungen

## Status

Akzeptiert am 08.08.2026.

## Entscheidung

Die historische Depotperformance wird je Währung aus rekonstruierten Beständen,
persistenten Kursen und Wertpapiercashflows berechnet. Der letzte bekannte Kurs
am oder vor dem Bewertungstag gilt; ein expliziter Kurs schlägt einen aus einem
Kauf oder Verkauf abgeleiteten Kurs desselben Tages. Fehlende Kurse werden nicht
durch Null, Interpolation oder eine andere Währung ersetzt.

Die Oberfläche weist absoluten Gewinn, einfache Rendite, zeitgewichtete Rendite
(TWR), exaktdatierte geldgewichtete Jahresrendite (XIRR) und annualisierte TWR
getrennt aus. Kauf, Verkauf, Ertrag und Gebühr werden als externe Cashflows
neutralisiert, damit TWR die Anlageentwicklung und XIRR die individuelle
Kapitalbindung beschreibt. Alle Berichte verwenden denselben Snapshot.

## Folgen

- Ergebnisse bleiben ohne implizite Währungsumrechnung fachlich nachvollziehbar.
- Fehlende Kurse machen betroffene Bewertungen und Kennzahlen ausdrücklich
  nicht berechenbar; veraltete Schlusskurse bleiben am Datum erkennbar.
- Benchmarkvergleich, Zielallokation und automatische Kursbeschaffung sind
  eigenständige spätere Funktionen.
