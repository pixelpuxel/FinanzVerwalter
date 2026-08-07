# Berichtswerkstatt

Stand: 07.08.2026

Dieses Dokument beschreibt den reproduzierbaren Sollzustand der
FinanzVerwalter-Berichtswerkstatt. Der gegenwärtige Kategoriebericht ist nur
ein erster vertikaler Slice und erfüllt diesen Sollzustand ausdrücklich noch
nicht.

## Implementierter Stand

Der erste echte Berichtswerkstatt-Slice ist umgesetzt:

- `TransactionReportQuery` bildet Zeitraum, Konten/Gruppen, Kategorien mit
  Unterbäumen, Klassen/Tags, Empfänger, Status, Betragsspanne, Volltext,
  Währungen sowie versteckte und ausgeschlossene Konten ab.
- Umbuchungen und Splitauflösung sind explizite Optionen.
- `TransactionReportEngine` erzeugt unveränderliche Fakten, trennt Währungen
  und verhindert die Doppelzählung von Haupt- und Splitbuchung.
- Gruppierung nach Kategorie, Empfänger, Konto, Klasse/Tag, Monat oder deutscher
  Steuerzuordnung liefert
  Einnahmen, Ausgaben, Saldo und referenzierte Fakten.
- Eine optionale zweite, abweichende Gruppierungsdimension bildet stabile
  kombinierte Gruppen für Bildschirm, Drill-down, CSV, PDF und Druck.
- Bei zweistufiger Gruppierung bildet die Engine nach jeder Primärgruppe eine
  eigene währungsgetrennte Zwischensumme. Deren Drill-down referenziert exakt
  die Vereinigung der untergeordneten Fakten.
- Buchungsdetails, primäre Zwischensummen und Gesamtsummen sind unabhängig
  schaltbar. Die optionalen Query-Felder bleiben beim Laden alter Vorlagen
  rückwärtskompatibel und werden ab Definitionsversion 3 gespeichert.
- Acht editierbare Standardberichte konfigurieren aktuelle-Jahr-Abfragen für
  Kategorie, Empfänger, Buchungsjournal, Cashflow, Kontobewegungen und
  Kategorie/Klasse, monatlichen Cashflow sowie deutsche Steuerzuordnungen. Der Steuerbericht filtert
  nicht gepflegte Steuerzeilen und gliedert danach nach vollständigem
  Kategoriepfad. Dieselben Definitionen sind deterministisch testbar und
  können als normale Vorlage gespeichert werden.
- Balken-, Linien-, Flächen- und Tortendiagramme für Einnahmen oder Ausgaben werden rein aus dem
  bestehenden Snapshot abgeleitet. Sie trennen Währungen, sortieren
  deterministisch. Balken und Torte fassen Werte hinter den größten elf
  centgenau als Restsegment zusammen; Linie und Fläche bleiben chronologisch
  und ungekürzt. Die Berichtstabelle und ihr Drill-down bleiben dabei
  erhalten. Steuerfilter, Diagrammart und Kennzahl werden ab
  Definitionsversion 4 rückwärtskompatibel gespeichert.
- Die SwiftUI-Werkstatt zeigt die Gruppen und einen Buchungs-Drill-down.
- Zwei Engine-Tests und die vollständige reale 2025-QIF-Abnahme prüfen
  Filterkombinationen und Splitinvarianten.
- Migration 13 speichert versionierte Query-Vorlagen mit eindeutigem Namen;
  Anlegen, Aktualisieren, Laden und Löschen sind in der Werkstatt verfügbar.
- CSV entsteht direkt aus dem Snapshot mit Metadatenblock, Semikolon, Komma
  oder Tabulator, UTF-8 oder ISO-8859-1 und deutschem Zahlenformat. Der
  Exporter besitzt einen bytegenauen Golden-Test.
- PDF entsteht ebenfalls direkt aus dem unveränderten Snapshot. A4-Hoch- und
  Querformat enthalten Metadaten, gruppierte Übersicht, Buchungs- und
  Splitpositionen, wiederholte Tabellenköpfe, alternierende Zeilen und
  Seitenzahlen.
- Ein semantischer PDFKit-Test öffnet das Ergebnis erneut und prüft ein
  mehrseitiges Dokument. Zusätzlich wurden Seite 1, eine Buchungsseite und
  die letzte Seite eines fünfseitigen Referenzberichts mit Poppler gerendert
  und visuell geprüft.
- PDF-Export und direkter macOS-Systemdruck verwenden denselben erzeugten
  Datenstrom und dieselbe unveränderliche Momentaufnahme.
- HTML entsteht bytegenau reproduzierbar aus demselben Snapshot, enthält
  semantische Tabellen, vollständige Metadaten und Druck-CSS und maskiert alle
  importierten Texte. Ein SHA-256-Golden-Test sichert den Datenstrom ab.
- XLSX entsteht als vollständiges Open-XML-ZIP-Paket mit Arbeitsblatt,
  Metadaten, Formatvorlagen und exakten numerischen Geldzellen für null bis
  vier Währungsnachkommastellen. Paket, CRC, XML, Formelinjektionsschutz,
  SHA-256-Goldenwert und ein optionaler echter LibreOffice-Rundlauf sind
  geprüft.
- `Kopieren` schreibt tabulatorgetrennten UTF-8-Text und dieselbe maskierte
  HTML-Darstellung gemeinsam in die Zwischenablage, sodass Tabellenprogramme
  und Textziele jeweils die passende Repräsentation wählen können.
- `Kontosalden und Nettovermögen` berechnet je Konto einen historischen
  Tagesabschluss aus Eröffnungssaldo und nicht stornierten Bewegungen seit dem
  Eröffnungsdatum. Konten, Gruppen, Währungen sowie versteckte, geschlossene
  und ausgeschlossene Konten sind filterbar. Aktiva, Passiva und Netto werden
  strikt je Währung ausgewiesen; Tabelle, CSV, mehrseitiges PDF und direkter
  Druck verwenden denselben Stichtagssnapshot.
- `Zeitvergleich` stellt zwei frei wählbare Intervalle als Gesamtsumme oder
  Monatsdurchschnitt gegenüber. Einnahmen, Ausgaben und Saldo können nach
  Kategorie, Empfänger, Konto, Klasse/Tag oder ungruppiert ausgewertet werden.
  Fehlende Vergleichsgruppen, Differenz, Prozentwert, getrennte Drill-downs
  und währungsgetrennte Gesamtsummen werden aus einem Snapshot erzeugt.
- `Budget Plan/Ist/Abweichung` wertet alle zwölf Monate eines frei beginnenden
  Geschäftsjahres oder einen Einzelmonat aus. Budgetfähige offene Konten,
  Splitanteile, vollständige Kategoriepfade, Plan, Ist, Abweichung,
  Zielerreichung und Drill-down werden fachlich konsistent behandelt.
- Beide Vergleichsberichte besitzen deterministisches Semikolon-CSV,
  mehrseitiges A4-PDF in Hoch-/Querformat und direkten Systemdruck aus
  derselben Momentaufnahme.

Noch offen sind weitere fachliche Standardberichte.

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

- Einnahmen/Ausgaben nach Kategorie *(buchungsbasiertes Preset umgesetzt)*
- Einnahmen/Ausgaben nach Empfänger *(buchungsbasiertes Preset umgesetzt)*
- Buchungsbericht *(buchungsbasiertes Preset umgesetzt)*
- Cashflow *(Konto/Kategorie-Preset umgesetzt)*
- Kontosalden und Nettovermögen *(Stichtagslogik, CSV, PDF und Druck umgesetzt)*
- Kategorie-, Klassen- und Tagbericht *(Kategorie/Klasse-Preset umgesetzt)*
- Zeitvergleich *(Summe/Monatsdurchschnitt, Drill-down, CSV, PDF und Druck umgesetzt)*
- Budgetabweichung *(Geschäftsjahr/Monat, Drill-down, CSV, PDF und Druck umgesetzt)*
- Deutscher Steuerbericht *(gepflegte Steuerzeilen, Kategorie-Drill-down und
  bestehende Exportpipeline umgesetzt)*
- Monatlicher Cashflow *(chronologische Monatsgruppierung, vollständige
  Linien-/Flächenzeitreihe und bestehende Exportpipeline umgesetzt)*

P1:

- Umsatzsteuerbericht
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

1. weitere fachliche Standardberichte
2. gespeicherte Spaltenauswahl je Berichtsvorlage
