# Berichtswerkstatt

Stand: 31.07.2026

Dieses Dokument beschreibt den reproduzierbaren Sollzustand der
FinanzVerwalter-Berichtswerkstatt. Der gegenwärtige Kategoriebericht ist nur
ein erster vertikaler Slice und erfüllt diesen Sollzustand ausdrücklich noch
nicht.

## Verifizierte Referenzfunktionen

Die Recherche stützt sich auf offizielle Lexware-Quellen:

- Das
  [FinanzManager-2021-Updatehandbuch](https://www.lexware.de/fileadmin/lego/finanzmanager/2021_updatehandbuch_finanzmanager.pdf)
  dokumentiert Filter, ein teilbares Kontoblatt, frei anordenbare und
  skalierbare Spalten sowie die historisch vorhandene Ein-/Zweizeilenansicht.
- Das
  [FinanzManager-2026-Updatehandbuch](https://www.lexware.de/fileadmin/support/handbuecher/2026/updatehandbuch_fima_2026_v33.pdf)
  dokumentiert kontextbezogene Auswertungen aus einer Buchung, den Bericht
  über sichtbare Buchungen, Konten-/Kategorie-/Textfilter, Mehrfachauswahl,
  Export und Druck.
- Die
  [FinanzManager-2026-Versionshinweise](https://finanzmanager-hilfe.lexware.de/releasenotes/finanzmanager_2026.htm)
  nennen Kategorieauswahl in Berichtsfiltern und eine umschaltbare
  Splitdarstellung.
- Die
  [FinanzManager-2027-Versionshinweise](https://finanzmanager-hilfe.lexware.de/releasenotes/finanzmanager_2027.htm)
  nennen zusätzliche Empfänger-/Verwendungszweckspalten und die Navigation
  in Berichtsgruppen.

Die genannten Quellen dienen der Funktionsanalyse. FinanzVerwalter bleibt
eine unabhängige Neuentwicklung und übernimmt weder fremden Quellcode noch
Grafiken oder Logos.

## Fachliches Abfragemodell

Eine gespeicherte `ReportDefinition` muss mindestens enthalten:

- Berichtsart und fachliche Version
- frei gewählter Zeitraum sowie Monat, Quartal, Jahr, Vorjahr und rollierende
  Zeiträume
- ein- oder ausgeschlossene Konten und Kontengruppen
- Kategorien einschließlich optionaler Unterbäume
- Klassen/Tags, Empfänger und Buchungsstatus
- Betragsbereich, Volltext im Verwendungszweck und Währungen
- Einbezug ausgeblendeter oder geschlossener Konten
- Behandlung von Splitbuchungen und Umbuchungen
- Zeilen- und Spaltendimension
- Sortierregeln, sichtbare Spalten, Zwischensummen und Gesamtsummen
- Darstellungsart, Titel und Regel für neu hinzukommende Kategorien

## Berechnungspipeline

1. Kontenmenge aus Konto- und Gruppenfilter bestimmen.
2. Buchungsfakten laden und Splitzeilen in eigenständige
   Auswertungsallokationen expandieren.
3. Umbuchungen, Stornos und ausgeblendete Konten nach Definition behandeln.
4. Zeitraum, Kategorieunterbaum, Tags, Empfänger, Status, Betrag und Text
   filtern.
5. Währungen niemals ohne explizite Wechselkursregel addieren.
6. Nach gewählten Dimensionen gruppieren, Zwischensummen und Gesamtsummen
   bilden.
7. Ein unveränderliches `ReportSnapshot` erzeugen. Drill-down-Zellen
   referenzieren die zugrunde liegenden Buchungs- oder Split-IDs.

Eine Hauptbuchung mit Splits darf niemals zusätzlich zu ihren Splitzeilen
gezählt werden. Diese Invariante benötigt einen Golden-Test.

## Standardberichte

P0:

- Einnahmen/Ausgaben nach Kategorie
- Einnahmen/Ausgaben nach Empfänger
- Buchungsbericht
- Cashflow
- Kontosalden und Nettovermögen
- Kategorie-, Klassen- und Tagbericht
- Zeitvergleich und Budgetabweichung

P1:

- Steuer-/Umsatzsteuerbericht
- Kredit- und Tilgungsbericht
- Depot-, Performance- und Steuerbericht
- Vertrags-, Inventar- und Vermietungsbericht

Jeder Bericht unterstützt Tabelle, Balken, Linie, Fläche oder Kreis, soweit
die Dimensionen fachlich dazu passen. Tabellen benötigen konfigurierbare
Spalten, Sortierung, Gruppierung, Drill-down und eine dauerhaft speicherbare
Vorlage.

## Ausgabe

Aus demselben `ReportSnapshot` entstehen:

- Bildschirmansicht
- Drucklayout mit Titel, Zeitraum, Filtern, Seitenzahl und Erstellungsdatum
- PDF
- CSV
- XLSX
- HTML
- Zwischenablage

Für jede Ausgabe wird ein kleiner deterministischer Referenzdatensatz
verwendet. PDF, CSV, XLSX und HTML erhalten semantische Golden-Tests; für PDF
kommt zusätzlich eine gerenderte Sichtprüfung hinzu.

## Umsetzungsreihenfolge

1. Buchungsbericht-Builder mit vollständigem Filtermodell
2. Gruppierung nach Konto, Kategorie oder Empfänger
3. Drill-down und gespeicherte Vorlagen
4. druckbares Snapshot-Layout und CSV
5. weitere Standardberichte und Diagrammtypen
6. PDF/XLSX/HTML sowie Golden-Tests

