# ADR 0032: Sichtmengengleicher Kontoblatt-CSV-Export

## Status

Angenommen am 07.08.2026.

## Kontext

Einzel- und Sammelkontoblatt konnten ihre aktuelle Sichtmenge drucken und als
PDF ausgeben, aber nicht als weiterverarbeitbare Tabelle exportieren. Ein
separates erneutes Abfragen der Buchungen für CSV könnte Filter,
Zukunftszeilen, sichtbare Spalten oder laufende Salden abweichend behandeln.

## Entscheidung

CSV verwendet denselben unveränderlichen `RegisterPrintSnapshot` wie PDF und
Systemdruck. Seine Spalten sind exakt die sichtbaren Registerspalten; jede
Zeile enthält dieselben bereits formatierten Werte einschließlich
vollständiger Kategorie-/Klassenpfade und kontenweisem Saldo. Titel,
Filterzusammenfassung und Erstellzeit bilden den Metadatenblock.

Der Benutzer wählt Semikolon oder Komma sowie UTF-8 oder Windows-1252 aus den
fachlich sinnvollen Kombinationen. Ausgabezeilen enden mit CRLF. Felder mit
Trennzeichen, Anführungszeichen oder Zeilenumbrüchen werden in Anführungszeichen
gesetzt und innere Anführungszeichen verdoppelt. Windows-1252 wird nie
verlustbehaftet erzeugt; nicht darstellbare Zeichen führen zu einer sichtbaren
Fehlermeldung.

## Folgen

PDF, Druck und CSV besitzen identische Zeilen- und Spaltenselektion. Ein CSV
ist für Tabellenkalkulationen geeignet, bleibt aber ausdrücklich eine
formatierte Sichtausgabe und kein vollständiges Sicherungs- oder
Reimportformat. Zukünftige Spalten werden automatisch aufgenommen, sobald sie
Teil des `RegisterPrintSnapshot` sind.
