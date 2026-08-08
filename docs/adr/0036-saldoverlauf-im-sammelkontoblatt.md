# ADR 0036: Saldoverlauf im Sammelkontoblatt

## Status

Angenommen am 07.08.2026.

## Kontext

Ein Verlauf aus einer gefilterten Buchungsmenge darf nicht als Kontostand
erscheinen. Außerdem sind Kontostände verschiedener Währungen nicht sinnvoll
addierbar und mehrere Buchungen eines Tages sollen den Graphen nicht unnötig
verdichten.

## Entscheidung

`CombinedRegisterChartEngine` erzeugt einen unveränderlichen, nach Währung
getrennten Tagessnapshot. Ohne Filter beginnt jede Serie mit der Summe der
Eröffnungssalden der eingeschlossenen offenen Konten. Chronologische
Buchungen verändern diesen Wert, Stornos nicht; pro Kalendertag bleibt der
Wert und die UUID der letzten Buchung erhalten.

Sobald die Sammelabfrage gefiltert ist, beginnt jede Serie bei null und zeigt
nur die kumulierten wirksamen Bewegungen der Sichtmenge. Stornos und
Umbuchungsseiten werden ausgeschlossen. Oberfläche und Accessibility nennen
diesen Modus ausdrücklich `Gefilterte Bewegungssumme`. Bei weniger als 30
Tageswerten zeichnet die Oberfläche Punkte. Hover wählt über die gespeicherte
UUID die letzte wirksame Buchung des Tages in derselben Tabelle. Haupt- und
zweite Sammelansicht verwenden denselben Snapshot.

## Folgen

Mehrere Währungen bleiben fachlich getrennt. Der Graph kann einen Filterwert
nicht mehr mit einem echten Saldo verwechseln. Tagesverdichtung hält auch
lange Buchungshistorien lesbar, während kleine Datenmengen direkt navigierbar
bleiben. Eine historische Währungsumrechnung findet bewusst nicht statt.
