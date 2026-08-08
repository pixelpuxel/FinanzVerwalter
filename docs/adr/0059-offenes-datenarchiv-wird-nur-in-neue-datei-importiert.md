# ADR 0059: Offenes Datenarchiv wird nur in neue Datei importiert

## Status

Angenommen am 08.08.2026.

## Kontext

Das offene `.finanzarchiv` aus ADR 0057 bildet sämtliche Anwendungstabellen,
Beziehungen und Originalanhänge portabel ab. Ein Rückimport darf dennoch
weder die aktive Finanzdatei teilweise verändern noch manipulierte,
unvollständige oder für eine andere Schemafassung bestimmte Inhalte
übernehmen. CSV und JSON parallel als Schreibquelle zu behandeln würde
zudem widersprüchliche Wahrheiten zulassen.

## Entscheidung

`data.json` ist die autoritative Importquelle; CSV bleibt ein verpflichtender,
offen lesbarer Spiegel. FinanzVerwalter akzeptiert nur Paketformat 1 und die
exakt aktuelle Datenbankschemaversion. Vor jeder JSON-Auswertung werden das
vollständige SHA-256-Manifest, die exakte dokumentierte Dateimenge, reguläre
Dateitypen, sichere relative Pfade und feste Ressourcenlimits geprüft.
Tabellen- und Spaltenmenge müssen dem frisch erzeugten Anwendungsschema exakt
entsprechen.

Der Import legt im Zielordner eine private neue Datenbank an, leert deren
Initialwerte und rekonstruiert in einer einzigen Transaktion jede Tabelle mit
unveränderten Primär- und Fremdschlüsseln. Anhangspayloads werden nur über den
erwarteten hashadressierten Pfad geladen und erneut nach Typ, Größe und SHA-256
geprüft. Exakte Zeilenzahlen, `foreign_key_check` und `integrity_check` sind
Freigabebedingungen. Erst danach wird die Datei auf `0600` gesetzt und atomar
als neues `.qdata`-Ziel veröffentlicht. Aktive oder vorhandene Dateien werden
nicht überschrieben. Archivierte Oberflächeneinstellungen werden gemeldet,
aber nicht automatisch angewendet.

## Folgen

- Ein Fehler hinterlässt weder eine teilweise importierte Zieldatei noch
  eigene Zwischenartefakte; die Quelldatei bleibt unverändert.
- Ein gültiges Archiv kann vollständig einschließlich Splits, Hierarchien,
  Tags und byteidentischen Originalanhängen wieder als Finanzdatei geöffnet
  werden.
- Archive älterer Schemaversionen benötigen künftig einen ausdrücklich
  versionierten Konverter; eine stille Interpretation findet nicht statt.
- CSV-Manipulation kann keine Datenbankwerte einschleusen. Ein späterer
  semantischer JSON/CSV-Vergleich kann ergänzend eingeführt werden.
