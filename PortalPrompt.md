# Reproduzierbarer Bauprompt – FinanzVerwalter-Desktopprojekt

## Ziel

Erstelle im Ordner
`/Users/gabrielschreiber/Documents/iPhone Apps/FinanzVerwalter` eine neue native
macOS-Desktopanwendung namens **FinanzVerwalter**. Die App bildet die belegbaren
Arbeitsabläufe einer klassischen deutschen Desktop-Finanzverwaltung fachlich
nach. Sie ist local-first, offline nutzbar,
tastaturfreundlich und für dichte Finanzdaten ausgelegt.

Eine bereitgestellte externe Master-Spezifikation ist vor der Umsetzung
vollständig zu lesen.

Lies außerdem vor jeder relevanten Änderung:

1. `/Users/gabrielschreiber/Documents/iPhone Apps/AGENTS.md`
2. `/Users/gabrielschreiber/Documents/iPhone Apps/FinanzVerwalter/Gedächtnis.md`
3. diese Datei

## Abgrenzung

Das Projekt ist eigenständig. Verwende keinen Quellcode, keine Assets, keine
Designvorlagen und keine Fachmodelle aus `Banking`, `FundOrt`,
`PortalSteuern` oder anderen Projekten dieses Workspaces. Der einzige
erlaubte projektübergreifende Zugriff ist der vom Nutzer verlangte sichere
Telegram-Arbeitsablauf. Zugangsdaten dürfen weder ausgegeben noch ins
Repository kopiert werden.

Der Produkt-, App-, Target- und Verzeichnisname ist ausschließlich
„FinanzVerwalter“. Fremde Produktbezeichnungen dürfen nur als erforderlicher,
eindeutig beschreibender Kompatibilitätsverweis verwendet werden. Es darf
keine wirtschaftliche Verbindung, Autorisierung oder Herkunftstäuschung
nahegelegt werden. Proprietärer Quellcode und geschützte Originalassets
dürfen nicht übernommen werden.

## Technische Basis

- Plattform: native macOS-App, Deployment Target macOS 14
- Sprache/UI: Swift 5 und SwiftUI
- Persistenz: System-SQLite über `SQLite3`, WAL, Foreign Keys
- Abhängigkeiten: keine externen Pakete
- Projekt: `FinanzVerwalter.xcodeproj`
- App-Bundle: `FinanzVerwalter.app`
- Bundle-ID im Entwicklungsstand: `de.pixelpuxel.finanzverwalter`
- Tests: XCTest

## Schichten

1. `Money.swift`: centgenaue Beträge, Parser und Rundung
2. `FinanceModels.swift`: reine Domänenmodelle und Invarianten
3. `SQLiteFinanceStore.swift`: Migrationen, QIF/CSV-Parser und atomare Repositories
4. `FinanceAppStore.swift`: Main-Actor-Use-Cases und UI-Zustand
5. `RootView.swift`: Desktop-Shell, Navigation, Werkzeug- und Statusleiste
6. `RegisterView.swift`: Kontoblatt, Suche, Sortierung und Buchungseditor
7. `SupportingViews.swift`: Cockpit, Konten, Kategorien, Berichte,
   Import/Export, Backup und Einstellungen

## Finanzielle Regeln

- Persistiere Geld ausschließlich als `Int64`-Minor-Units.
- Parse deutsche Eingaben und Betragsausdrücke über `Decimal`; runde explizit
  auf die Nachkommastellen der jeweiligen Währung.
- Validiere `Summe(Splits) == Hauptbetrag` vor jedem Speichern.
- Erzeuge, ändere und lösche beide Transferseiten atomar.
- Berechne Salden als Eröffnungssaldo plus relevante Buchungen.
- Schütze abgeglichene Buchungen vor stiller Änderung.
- Übernimm dasselbe Importpaket anhand eines SHA-256-Hashes nur einmal.
- Schreibe für jede Mutation ein append-only Auditereignis.

## UI-Soll

Das Fenster besitzt:

- native Menüleiste und anpassbare Tastaturkommandos
- obere Werkzeugleiste mit Neu, Speichern, Suchen, Aktualisieren, Abgleichen
- linke gruppierte Kontenleiste mit Salden
- zentrale tab-/auswahlbasierte Arbeitsfläche
- optionalen rechten Inspektor
- untere Statuszeile

Hauptbereiche:

- Cockpit
- Konten
- Sammelkontoblätter
- Zahlungsverkehr
- Kalender & Prognose
- Budget
- Auswertungen
- Wertpapiere & Depots
- Kredite & Vermögen
- Verträge
- Inventar
- Adressen & Mandate
- Regeln
- Import/Export
- Einstellungen

Das Kontoblatt ist der primäre Bildschirm. Es zeigt Datum, Wertstellung,
Belegnummer, Empfänger, Verwendungszweck, Kategorie, Klasse/Tags, Betrag,
Status und laufenden Saldo. Es unterstützt Inline-Eingabe, Splitdialog,
Volltextfilter, Mehrfachauswahl, erwartete Zukunft und Shortcuts.
Kategoriepfade müssen in der Tabelle vollständig aus dem Hierarchiebaum
gebildet werden. Zeige sie einzeilig, kürze bei Platzmangel in der Mitte und
lege den vollständigen Pfad als Tooltip ab. Bei Splits sind alle
unterschiedlichen Splitpfade in stabiler Reihenfolge sichtbar.

Implementiere für normale Buchungen eine einblendbare Inline-Zeile direkt am
Kontoblatt. Sie enthält Datum, ausschließlich offene Konten, Empfänger,
Verwendungszweck, vollständigen Kategoriepfad, Status und Betrag. Nutze für
den Betrag `Money(evaluating:)` und normalisiere Texte erst beim Speichern.
Eingabe im Betragsfeld speichert, Esc leert ohne Mutation, Tab bleibt normale
Feldnavigation. Nach Erfolg bleiben Datum und Konto erhalten; Empfänger,
Zweck, Kategorie und Betrag werden geleert und der Fokus kehrt zum Empfänger
zurück. Die resultierende einfache Buchung besitzt Wertstellung gleich
Buchungsdatum, manuelle Herkunft, keine Transfer-/Importidentität und keine
Splits. Speichere sie über denselben atomaren Storepfad samt Audit und
persistenter Undo-Momentaufnahme. Geschlossene oder fehlende Konten sowie
ungültige Beträge dürfen keine Teilmutation erzeugen. Komplexe Buchungen
bleiben im vollständigen Dialog.

Sortiere das Einzelkontoblatt auf- oder absteigend nach jeder
`RegisterColumn`: Datum, Wertstellung, Belegnummer, Status, Empfänger,
Verwendungszweck, vollständigem Kategoriepfad, vollständigen Klassen-/Tags,
Konto, Betrag und Saldo. Verwende für deutsche Texte eine
diakritikaunabhängige, case-insensitive und numerische `de_DE`-Sortierung.
Gleiche Primärwerte werden stets nach Buchungsdatum und UUID stabil
aufgelöst; das Ergebnis darf nicht von der Eingabereihenfolge abhängen.
Berechne laufende Salden weiterhin ausschließlich chronologisch je Konto und
sortiere danach nur die fertigen Zeilen, damit eine Kategorie- oder
Betragssortierung den fachlichen Saldo einer Buchung nicht verändert.
Persistiere Spalte und Richtung in den lokalen Einstellungen und optional in
benannten Kontoblattansichten. Alte Ansichten ohne diese optionalen Felder
werden als Datum aufsteigend geöffnet. Binde dieselben Komparatoren an die
nativen macOS-Tabellenköpfe: Ein Klick wählt die Spalte aufsteigend, der
nächste Klick kehrt die Richtung um. Menü, Tabellenkopfpfeil und persistierter
Zustand müssen stets dieselbe Spalte und Richtung zeigen.

Biete für die fachliche Betragsspalte einen persistenten Ansichtsmodus
`Betrag` oder `Soll / Haben`. Im getrennten Modus ersetzt genau das Paar
`Soll`, `Haben` die eine Betragsspalte an derselben Position. Zeige negative
Buchungen als positiven Absolutbetrag ausschließlich unter Soll, positive
ausschließlich unter Haben und Null in beiden leer; verändere den gespeicherten
vorzeichenbehafteten Betrag nicht. Sortierung, Accessibility, Einzel-, Zweit-
und Sammelkontoblatt, benannte Ansichten sowie PDF, Druck und CSV müssen exakt
dieselbe Spaltenfolge verwenden. Speichere den Modus in Ansichten optional;
alte Ansichten ohne Feld öffnen weiterhin die einzelne Betragsspalte.

Für die direkte Ausgabe von Einzel- und Sammelkontoblättern gilt
reproduzierbar: Erzeuge genau einen unveränderlichen `RegisterPrintSnapshot`
aus der aktuellen Sichtmenge, der gewählten Spaltenreihenfolge, den
kontenweisen laufenden Salden und den vollständigen Kategorie-/Klassenpfaden.
PDF, Systemdruck und CSV dürfen keine eigene Buchungsabfrage ausführen. CSV
enthält Titel, Filter, UTC-stabile deutsche Erstellzeit und exakt die
sichtbaren Spalten. Biete Semikolon/UTF-8, Komma/UTF-8 und
Semikolon/Windows-1252 an, verwende CRLF und RFC-4180-artige Maskierung und
brich ohne verlustbehaftete Zeichenersetzung ab. Auch berechnete
Zukunftszeilen des Sammelkontoblatts werden ausschließlich dann exportiert,
wenn sie in der Sichtmenge enthalten sind.

## Umsetzungsreihenfolge

1. Projekt muss kompilieren und ein leeres lokales Finanzfile öffnen.
2. SQLite-Schema plus Migrationstests fertigstellen.
3. Kontoanlage, Buchung, Kontoblatt und Bericht als vertikalen Slice bauen.
4. CSV/QIF-Import mit Vorschau und Dublettenprüfung ergänzen.
5. Splits, Transfers, Kategorien, Klassen, Regeln und Abgleich ergänzen.
6. Backup/Restore mit Integritätsprüfung ergänzen.
7. P1-Planung (Serientermine, Prognose, Budget), Simulator-Banking und
   Vermögensmodule ergänzen.
8. Accessibility, Performance, Security und vollständige UI-Tests härten.
9. Release bauen, nach `~/Applications/FinanzVerwalter.app` installieren, starten
   und mit Screenshots sichtbar prüfen.

## Aktueller verifizierter Meilenstein

Migrationen 1 bis 38 sowie die in diesem Dokument beschriebenen lokalen
Konto-, Buchungs-, Berichts-, Regel-, Banking-, Import-, Budget- und
Sicherungs- und Prognosekerne sind implementiert. Die jüngste vollständige
Abnahme umfasst 180 XCTest-Fälle: 178 bestanden, zwei private opt-in-Tests
wurden ohne ihre ausdrücklich benötigten lokalen Voraussetzungen
erwartungsgemäß übersprungen, 0 Fehler. Der private echte 2025-QIF-Test
bestand zusätzlich in einem früheren separaten Lauf mit einer danach
gelöschten temporären Kopie. Die arm64-Release-App ist unter
`/Applications/FinanzVerwalter.app` und `~/Applications` installiert. Die
installierte ausführbare Datei besitzt SHA-256
`52ba7894559e153ec3023bbb25c090fb32bb70d962ce03fcee8ca2a18c11b12e`.
Details und der ehrliche Nachweis der wegen der gesperrten macOS-Sitzung noch
ausstehenden sichtbaren Abnahme stehen in `Gedächtnis.md`.

Migration 11 ergänzt `account_groups` und erweitert `accounts` um Kurzname,
Beschreibung, Gruppe, IBAN, BIC, maskierte Kontonummer, Inhaber,
Eröffnungsdatum, Kreditlimit, Onlinekennzeichen, vier getrennte
Einbeziehungsregeln, Abrufzeit, Banksaldo und Abrufstatus. Kontonamen sind
Pflicht, Kreditlimits nicht negativ, IBANs werden normalisiert und mit Mod 97
validiert, Gruppen müssen existieren. Kontengruppen besitzen Reihenfolge und
Aktivstatus. Die Kontenübersicht zeigt Gruppensummen, Saldo, verfügbaren Betrag,
Abrufstatus und letzten Abruf; der Editor kann bestehende Konten vollständig
ändern. Toolbar und Kontextmenü öffnen das gewählte Konto tatsächlich im
Kontoblatt, Banking-Abruf oder Abgleich. Ausblenden, Schließen und
Wiederöffnen laufen über den auditierten Konto-Speicherpfad. Vor dem Schließen
zeigt ein Bestätigungsdialog Saldo und die Anzahl aktiver Serien,
Daueraufträge und noch offener Zahlungsaufträge. Buchungen werden dabei nicht
gelöscht; ein geschlossenes oder ausgeblendetes Konto darf nicht als aktive
globale Kontoauswahl zurückbleiben.
Jede aktive Gruppenkarte besitzt zusätzlich `Gruppe abrufen`. Übergib dabei
die IDs ausschließlich ihrer offenen Online-Konten als typisierten
`BankingLaunchScope`. Ein Resolver betrachtet nur aktive Verbindungen und
aktive eindeutige Zuordnungen, wählt deterministisch die Verbindung mit den
meisten passenden lokalen Konten und liefert ausschließlich deren externe
IDs. Bei Gleichstand entscheidet die stabile Verbindungs-UUID. Andere aktive
Kontenzuordnungen derselben Verbindung dürfen nicht in die Abrufauswahl
gelangen. Zeige ausgewählte und nicht zugeordnete Gruppenkonten vor dem
Abruf. Trenne in der Zuordnungszeile die temporäre Abrufauswahl von der
persistierten Aktivierung der Zuordnung.
Vermögenssumme, Budget-Ist, Berichte und Prognose müssen ihren jeweiligen
Einbeziehungsschalter beachten. Konten- und Gruppensalden sind in ihrer
jeweiligen Währung zu formatieren. Ohne FX-Tabelle darf das Nettovermögen nur
Konten in der Basiswährung summieren und muss ausgelassene
Fremdwährungskonten sichtbar kennzeichnen.

Migration 12 stellt neun fachliche Standardkontengruppen sicher:
Bankkonten, Kreditkarten, Bargeld, Depots, Kredite, Vermögen,
Verbindlichkeiten, Forderungen und Sonstige. Sie ordnet jedes vorhandene
Konto ohne Gruppe anhand seines `AccountType` zu. Der Mehrkonten-QIF-Commit
weist dieselben Gruppen neuen Konten sofort zu. Der Kontoeditor schlägt bei
einem neuen Konto die typgerechte Gruppe vor, lässt aber eine bewusste
abweichende Zuordnung zu.

Die verbindliche Soll-Ist-Matrix liegt in `docs/Anforderungsmatrix.md`.
Architekturentscheidungen liegen als ADRs in `docs/adr/`. Ein anderer Agent
muss diese Dateien vor der nächsten Implementierung lesen und darf einen
`Teilweise`- oder `Offen`-Eintrag nicht als fertige Funktion darstellen.

Kategorien sind ein eigener Hauptbereich. Speichere Ober- und
Unterkategorien über `parent_id`, verhindere Selbstbezug und Zyklen und
erlaube nur Eltern derselben Einnahmen-/Ausgabenart. In allen Auswahlfeldern
und Kontoblattspalten ist der vollständige Pfad
(`Oberkategorie › Unterkategorie`) anzuzeigen.

Ergänze die Kategorieverwaltung um eine deterministische Baumfilterung. Zerlege
den normalisierten Suchtext an Leerraum und verlange, dass jedes Token in der
gemeinsamen Suchfläche aus vollständigem Kategoriepfad, Beschreibung,
Kategorieart, deutscher Steuerzeile und US-Steuerzeile vorkommt. Normalisiere
mit deutscher Locale case-, diakritika- und breitenunabhängig. Nimm zu jedem
Treffer sämtliche Ahnen in die sichtbare ID-Menge auf, damit der Baumweg nicht
abbricht. Ein Schalter blendet inaktive Treffer aus; inaktive Ahnen aktiver
Treffer bleiben als notwendige Struktur sichtbar. Zeige bei aktiver Suche den
vollständigen Pfad als kompakte zweite Zeile mit ungekürztem Hilfetext und für
eine leere Treffermenge einen erklärenden Leerzustand. Teste tiefe Pfade,
Mehrwortsuche, Diakritika, Metadaten, inaktive Blätter und inaktive Ahnen als
reine Logik ohne UI-Abhängigkeit.

Das Kontoblatt berechnet einen laufenden Saldo getrennt je Konto und Währung.
Beginne mit dem Eröffnungssaldo, sortiere nach Buchungsdatum und UUID und
ignoriere stornierte Beträge. Zeige `Saldo` unmittelbar rechts von `Betrag`.
Ein gemeinsamer persistierter Zeilenmodus schaltet Konto- und
Sammelkontoblatt zwischen einer festen 20-Pixel-Einzeile und einer festen
38-Pixel-Zweizeile um. Die Zweizeile darf Wertstellung, Memo, Referenz und
Tags ergänzen; die feste Höhe verhindert Layoutflattern bei großen Dateien.

Der bestehende Kategoriebericht ist ausdrücklich kein vollständiges
Berichtssystem. Die verbindliche Query-, Snapshot-, Drill-down-, Vorlagen-,
Druck- und Exportarchitektur sowie die recherchierten offiziellen
Referenzfunktionen stehen in `docs/Berichtswerkstatt.md`.

Der implementierte erste Berichtswerkstatt-Slice verwendet
`TransactionReportQuery`, `TransactionReportFact`,
`TransactionReportGroup`, `TransactionReportSnapshot` und
`TransactionReportEngine`. Die Engine expandiert eine Splitbuchung entweder
in exakt ihre Splitzeilen oder wertet sie als Gesamtbuchung; Haupt- und
Splitbetrag dürfen nie gleichzeitig summiert werden. Filter werden als
UND-Verknüpfung angewandt. Mehrere gewählte Einzelkonten und Kontengruppen
bilden innerhalb der Kontodimension eine Vereinigungsmenge. Kategorien und
Tags können ihre Nachkommen einschließen. Status, Empfänger, Betragsspanne,
Volltext, Währung, versteckte Konten, Berichts-Ausschluss und Transfers sind
weitere unabhängige Dimensionen.

Gruppen nach Kategorie, Empfänger, Konto oder Klasse/Tag enthalten
währungsgetrennte Einnahmen, Ausgaben, Saldo und die Menge ihrer
Auswertungsfakt-IDs. Der Drill-down darf ausschließlich Fakten dieser
ID-Menge zeigen. Gruppensummen verschiedener Währungen werden nie addiert.
Die reale QIF-Abnahme muss für jede importierte Buchung beweisen, dass die
Summe ihrer Berichtsfakten wieder exakt dem Originalbetrag entspricht.

Migration 13 speichert Berichtsvorlagen in `report_templates`. Eine Vorlage
besitzt UUID, innerhalb der Finanzdatei eindeutigen Namen, fachliche
Definitionsversion und das mit sortierten Schlüsseln codierte
`TransactionReportQuery`-JSON. Anlegen/Aktualisieren und Löschen laufen in
einer SQLite-Transaktion mit Audit. Beim Laden werden alle UI-Filter,
Splitoption, Gruppierung und Sortierung aus der Query wiederhergestellt.

`TransactionReportCSVExporter` erzeugt ausschließlich aus einem bereits
berechneten Snapshot. Vor der Tabelle stehen Berichtstitel, Zeitraum,
Filterzusammenfassung, Erstellungszeit und Basiswährung. Unterstützt werden
Semikolon, Komma und Tabulator sowie UTF-8 und ISO-8859-1 ohne verlustbehaftete
Konvertierung. Geld wird deterministisch aus Minor-Units als deutsches
Dezimalformat ohne Binär-Float geschrieben; Felder mit Trennzeichen,
Anführungszeichen oder Zeilenumbrüchen folgen RFC-4180-Escaping.

Eine Berichtsvorlage ab Definitionsversion 3 speichert zusätzlich die drei
optionalen Darstellungsfelder `includeDetailRows`, `includeSubtotals` und
`includeGrandTotals`. Fehlen sie in älterem JSON, gelten alle drei Bereiche
als sichtbar. Bei einer zweiten Gruppierungsdimension folgen auf die stabil
sortierten Detailgruppen währungsgetrennte Primär-Zwischensummen. Ihre
Faktenmenge ist exakt die Vereinigung der untergeordneten Gruppen, sodass der
Drill-down dieselben Buchungen zeigt. CSV, PDF und
`TransactionReportHTMLExporter` verwenden ausschließlich den bereits
berechneten Snapshot und beachten dieselben Sichtbarkeitsschalter. HTML ist
UTF-8, semantisch, druckoptimiert, vollständig HTML-maskiert und durch einen
bytegenauen SHA-256-Golden-Test reproduzierbar abgesichert. PDF erzeugt auch
bei vollständig ausgeblendeten Tabellen ein gültiges Metadatenblatt.

Ab Definitionsversion 4 speichert die Query zusätzlich die optionalen Felder
`requireGermanTaxAssignment`, `visualization` und `chartMetric`. Fehlende
Felder aus älteren Vorlagen bedeuten: kein Steuerfilter, Tabelle und Ausgaben.
Erweitere `ReportGrouping` um `germanTaxLine` und `month` und ergänze den Katalog um den
Standardbericht `Deutscher Steuerbericht`. Er läuft im aktuellen lokalen
Kalenderjahr, expandiert Splits, verwirft Fakten ohne nichtleere deutsche
Steuerzeile und gruppiert zuerst nach Steuerzeile, dann nach vollständigem
Kategoriepfad. Übernimm die Steuerzeile in jeden Berichtsfakt und in den
Volltextindex; die Detailtabelle zeigt sie als zweite, zurückhaltende Zeile
unter der Kategorie.

Implementiere `ReportChartEngine` als reine Ableitung eines bereits
berechneten `TransactionReportSnapshot`. Akzeptiere Einnahmen oder Ausgaben,
verwende ausschließlich Detailgruppen und erzeuge eine `ReportChartSeries`
je Währung. Für Rangdiagramme sortiere deterministisch nach Betrag absteigend
und bei Gleichstand nach Bezeichnung. Zeige dort standardmäßig höchstens zwölf
Segmente: Bei mehr Werten bleiben elf sichtbar, alle übrigen werden mit
exakter Minor-Unit-Summe und vereinigten Fakten-IDs zu `Weitere (n)`
zusammengefasst. Zeitreihen werden dagegen nach Bezeichnung chronologisch und
ohne Kürzung oder Restsegment ausgegeben. Addiere niemals verschiedene
Währungen. Falls es bei ungruppierter Abfrage keine Detailgruppen gibt, leite
je Währung einen Gesamtwert direkt aus den Snapshot-Summen ab.

Das UI bietet Tabelle, Balken, Linie, Fläche und Torte sowie Einnahmen oder Ausgaben als
Kennzahl. Verwende Swift Charts, formatiere sichtbare Summen über `Money`,
beschrifte Segmente für VoiceOver und trenne mehrere Währungen horizontal in
eigene Karten. Das Diagramm ergänzt die bestehende Tabelle; Filter,
Gruppentabelle, Fakten-Drill-down, CSV, HTML, XLSX, PDF und Systemdruck bleiben
auf demselben unveränderlichen Snapshot. Teste Steuerfilter inklusive Splits,
vollständigen Kategoriepfad, Vorlagen-Rückwärtskompatibilität, Roundtrip der
Version-4-Felder, deterministische Top-N-Reihenfolge, exakte Restaggregation,
Fakten-IDs und Währungstrennung. Ergänze den Standardbericht `Monatlicher
Cashflow`: aktuelles lokales Kalenderjahr, Gruppierung nach stabilem `yyyy-MM`,
aufsteigende Zeitreihenfolge, Liniendarstellung und Ausgabenkennzahl. Ein Test
mit mindestens 14 Monaten belegt, dass die Zeitreihe vollständig bleibt und
exakt dieselbe Faktenmenge wie der Snapshot verwendet.

`TransactionReportXLSXExporter` erzeugt ohne externe Bibliothek ein valides,
deterministisches Open-XML-ZIP-Paket mit genau einem Blatt `Bericht`.
Metadaten, Gruppen, Details und Gesamtsummen stammen aus demselben Snapshot.
Texte sind Inline-Strings, werden auf gültige XML-Zeichen begrenzt und niemals
als Formel geschrieben. Geldzellen bleiben numerisch und erhalten ein
Format für exakt null bis vier ISO-Nachkommastellen. Der interne ZIP-Writer
verwendet feste Metadaten, UTF-8-Pfade, Store-Kompression, CRC-32,
Zentralverzeichnis und stabile alphabetische Eintragsreihenfolge. Prüfe das
Paket bytegenau per SHA-256, vollständig per `unzip -t`, semantisch per XML
und optional durch echten LibreOffice-Import/CSV-Rundlauf.

`TransactionReportClipboardExporter` liefert parallel tabulatorgetrennten
UTF-8-Text und HTML aus demselben Snapshot. Der explizite UI-Befehl
`Kopieren` leert die allgemeine macOS-Zwischenablage und schreibt beide Typen,
ohne eine neue Berichtsauswertung auszulösen.

Die gemeinsame Massenorganisation erhält eine Menge Buchungs-UUIDs, einen
expliziten Schalter samt optionaler Zielkategorie sowie optional eine
vollständig ersetzende Menge aktiver Klassen/Tags. Prüfe vor jeder Mutation,
dass alle UUIDs und gewählten Ziele existieren. Abgeglichene Buchungen und
Umbuchungen sind immer geschützt; Splitbuchungen sind nur dann geschützt,
wenn ihre einfache Kategorie ersetzt werden soll. Eine reine Änderung der
Tags auf Buchungsebene lässt getrennte Split-Tags unverändert. Führe alle
Änderungen samt genau einer Versionsfortschreibung pro Buchung und Audit in
einer SQLite-Transaktion aus. Die Oberfläche zeigt zuvor Anzahl und Summen
getrennt nach Währung und verlangt eine zweite Bestätigung.

Ein vollständiger QIF-Export kann viele Konten, Kategorien, Klassen,
Vorlagen und Wertpapierabschnitte enthalten. Solche Pakete dürfen niemals
still in ein einzelnes Zielkonto importiert werden. Analysiere zuerst
Encoding, Header und Kontoblöcke, zeige eine Zuordnungsvorschau und übernimm
erst nach ausdrücklicher Bestätigung. Reale Referenzdateien bleiben außerhalb
des Repositorys; Tests verwenden nur synthetische oder anonymisierte Daten.

Der reproduzierbare Paketimport arbeitet so:

- Text als UTF-8 oder ISO-8859-1 lesen und CRLF/CR zu LF normalisieren.
- `!Account`-Datensätze und `!Type:`-Abschnitte als Zustandsfolge parsen.
- Konten anhand des normalisierten Namens vorhandenen Konten zuordnen oder
  als neue `FinanceAccount`-Objekte vorbereiten.
- Kategorien am Doppelpunkt in eine Hierarchie zerlegen; Eltern immer vor
  Kindern anlegen und vorhandene vollständige Pfade wiederverwenden.
- `Bank`, `Cash`, `CCard` und sonstige normale Kontoblätter mit Datum,
  Betrag, Empfänger, Memo, Referenz, Kategorie und Splits parsen.
- Beträge mit deutschem oder US-Dezimal-/Tausendertrennzeichen ohne
  binäre Fließkommazahlen in `Int64`-Minor-Units umwandeln.
- Depot-, Klassen- und Merkpostendatensätze in der Vorschau quantifizieren,
  aber nicht in ein unpassendes Kontobuchungsmodell zwingen.
- Neue Konten, neue Kategorien, Buchungen, Splits, Paketfingerabdruck und
  Auditereignis in genau einer SQLite-Transaktion schreiben.
- SHA-256 des Originalpakets verhindert eine zweite Übernahme.

Der Test `testQIFPackageCreatesAccountsHierarchyAndTransactionsAtomically`
nutzt ausschließlich synthetische Daten. Eine reale lokale Abnahme kann über
`FINANZVERWALTER_REAL_QIF` oder eine nur lokal vorhandene Datei
`/tmp/finanzverwalter-real-qif-acceptance.qif` aktiviert werden; ohne Datei
wird dieser Test übersprungen. Nie einen realen Finanzexport, seinen Inhalt
oder persönliche Pfade committen.

Für Serientermine gilt reproduzierbar:

- Persistenz in `scheduled_transactions` ab SQLite-Migration 4.
- Migration 38 ergänzt `transaction_template_json` als optionalen,
  deterministisch codierten vollständigen Buchungsinhalt. Ein aus dem
  Kontoblatt erzeugter Serienentwurf bewahrt Notiz, Empfängerakte, Tags,
  Splits samt Split-Tags und MwSt.-Werten sowie Fremdwährungsbetrag und Kurs.
  Referenz, Transfer-, Import-, Provider-, Bank- und Abgleichsidentitäten
  werden niemals übernommen.
- Einzelne geänderte oder übersprungene Instanzen werden ab Migration 33 in
  `scheduled_transaction_exceptions` gespeichert. Pro Serie und
  ursprünglichem Fälligkeitsdatum existiert höchstens eine Ausnahme.
- Änderungen dieser und aller folgenden Instanzen werden ab Migration 34 in
  `scheduled_transaction_revisions` gespeichert. Pro Serie und
  ursprünglichem Beginn existiert höchstens ein versionierter Änderungspunkt.
- Geld als `Int64`-Minor-Units, Fälligkeiten als kalendarisches ISO-Datum.
- Monatsbasierte Rhythmen erhalten die Monatsende-Semantik, auch über den
  29. Februar eines Schaltjahres.
- Jede virtuelle Instanz trägt
  `schedule:<Serien-UUID>:<Unixzeit der Fälligkeit>` als Herkunftskennung.
- Eine verschobene Instanz behält diese Herkunftskennung des ursprünglichen
  Fälligkeitsdatums. Dadurch bleiben Identität, Materialisierungsprüfung und
  Rücksetzen unabhängig vom wirksamen neuen Datum stabil.
- Eine geänderte Einzelinstanz kann Fälligkeit, Empfänger,
  Verwendungszweck, Kategorie einschließlich `keine Kategorie` und Betrag
  vollständig überschreiben. Eine übersprungene Instanz wird nicht in die
  Prognose aufgenommen, bleibt aber als rücksetzbare Ausnahme sichtbar.
- Solange Betrag und Kategorie unverändert bleiben, erzeugt eine Serie mit
  vollständigem Buchungsinhalt pro Instanz neue Buchungs- und Split-UUIDs und
  bewahrt Splits, Tags, MwSt. und Fremdwährung. Ändert eine Einzelinstanz oder
  Revision Betrag beziehungsweise Kategorie, entferne Splits, MwSt.- und
  Fremdwährungsdetails statt einen inkonsistenten strukturierten Beleg zu
  erzeugen. Die resultierende einfache Instanz muss weiterhin validieren.
- Eine Serienrevision überschreibt ab ihrer ursprünglichen Fälligkeit Datum,
  Empfänger, Verwendungszweck, Kategorie und Betrag. Die unveränderte
  Frequenz läuft vom neuen Datum aus weiter; die n-te wirksame Instanz behält
  die Ursprungskennung der n-ten kanonischen Instanz. Eine spätere Revision
  löst den wirksamen Verlauf erneut ab. Einzelausnahmen werden danach
  angewendet und können eine einzelne revidierte Instanz übersteuern.
- Speichern einer Revision ersetzt atomar eine Einzelausnahme am gleichen
  Ursprungstermin und auditiert beide Mutationen. Löschen der Revision stellt
  ab diesem Termin den vorherigen Serienverlauf wieder her.
- Die Vorschau filtert Herkunftskennungen, die bereits als echte erwartete
  Buchung vorhanden sind, damit kein realer Vorgang doppelt zählt.
- Der Prognosesaldo beginnt mit Eröffnungssaldo plus nicht stornierter,
  nicht erwarteter Buchungen bis heute und addiert erwartete sowie noch
  virtuelle Serientermine bis zum jeweiligen Stichtag.
- Biete Liste, Monat und Woche als segmentierte Kalenderansichten an. Erzeuge
  Monat und Woche mit einem auf Montag beginnenden gregorianischen Kalender
  und mindestens vier Tagen in der ersten ISO-Woche. Eine Woche hat exakt
  sieben Zellen; ein Monat wird vom Montag der ersten berührten Woche bis zum
  Sonntag der letzten berührten Woche auf 35 oder 42 Zellen aufgefüllt.
- Führe reale Buchungen und noch nicht materialisierte Serientermine nur für
  die Kalenderdarstellung zusammen. Klassifiziere virtuelle Serientermine als
  `regelmäßig`, echte Statuswerte `expected` als `erwartet`, `pending` als
  `vorgemerkt`, `booked`/`cleared`/`reconciled` als `gebucht` und `cancelled`
  als `storniert`. Jede Klasse hat eine konsistente Farbe, sichtbare Legende
  und vollständige Accessibility-Beschriftung.
- Filtere Kalender und Serienliste kombinierbar nach Konto, Kategorie und
  Klasse/Tag. Zeige Kategorie und Klasse immer als vollständigen Pfad. Ein
  gewählter Hierarchieknoten schließt alle Nachfahren ein; direkte Felder und
  alle Splitzeilen müssen beim Kategorie- und Klassenfilter geprüft werden.
- Navigation über vorherigen Zeitraum, `Heute` und nächsten Zeitraum muss
  Monats-, Schaltjahres- und Jahresgrenzen deterministisch erhalten.
- Mache ausschließlich erwartete Buchungen ohne verknüpftes Umbuchungspaar
  sowie virtuelle regelmäßige Termine ziehbar. Eine Kalenderzelle nimmt ihre
  stabile interne Kennung entgegen, validiert vor einer Mutation und verlangt
  eine Bestätigung mit Quell- und Zieldatum. Ziele vor dem heutigen lokalen
  Tag und der identische Tag sind unzulässig. Reale erwartete Buchungen werden
  vollständig mit neuem Buchungsdatum und gegebenenfalls mitlaufender
  Wertstellung über den vorhandenen auditierbaren Buchungsspeicher geändert.
  Ein virtueller Termin wird als persistente, rücksetzbare Einzelausnahme mit
  unveränderter Serien-ID und ursprünglicher Fälligkeitskennung verschoben.

Für Budgets gilt reproduzierbar:

- `budgets` und `budget_lines` werden ab SQLite-Migration 5 gespeichert.
- Ein Budget definiert Name, Startjahr, Startmonat, Währung und Aktivstatus;
  zwölf Monate können dadurch auch ein freies Geschäftsjahr abbilden.
- Ein Monatsplan ist pro Budget, Kategorie, Jahr und Monat eindeutig.
- Planwerte sind editierbare positive Minor-Units; das Ist wird ausschließlich
  aus nicht stornierten, nicht als Transfer verknüpften Buchungen berechnet.
- Der wirksame Plan eines Monats ist `Basisplan + eingehender Übertrag`.
  Ausgaben-Ist wird als positiver Verbrauch dargestellt; Einnahmen-Ist als
  positiver Zufluss. Der Monatssaldo ist bei Ausgaben `wirksamer Plan - Ist`
  und bei Einnahmen `Ist - wirksamer Plan`.
- Roll-over besitzt die Modi `aus`, `nur positive Salden` und `positive und
  negative Salden`. Die zuletzt gesetzte Betriebsart gilt innerhalb einer
  Kategorie für Folgemonate weiter, auch wenn dort keine eigene Planzeile
  existiert. Der ausgehende Übertrag ist je nach Modus null, `max(Saldo, 0)`
  oder der vollständige Saldo; er wird im nächsten Geschäftsmonat zum
  Basisplan addiert. Die Reserve ist die Summe aller ausgehenden Überträge.
- Speichere Jahreswerte für eine Kategorie als atomaren Zwölfmonats-Batch.
  Leere/mehrdeutige Budgetnamen sowie Unicode-, Groß-/Kleinschreibungs- und
  Diakritikvarianten bestehender Namen werden abgewiesen. Eine Budgetkopie
  überträgt alle zwölf Monatspositionen relativ zum neuen Geschäftsjahresstart
  mit frischen Zeilen-IDs und unveränderten Roll-over-Modi. Umbenennen und
  Löschen sind atomar; Löschen entfernt nur Budget und Planzeilen, nie die
  zugrunde liegenden Buchungen.
- Erfüllungsgrade werden dezimal berechnet und explizit auf ganze Prozent
  gerundet; Geldbeträge bleiben weiterhin frei von IEEE-754-Floats.

Für den Banking-Simulator gilt reproduzierbar:

- `payment_orders` wird ab SQLite-Migration 6 gespeichert; TAN- oder
  Freigabecodes besitzen absichtlich keine Persistenzspalte.
- IBANs werden normalisiert und mit der ganzzahligen Mod-97-Prüfsumme
  validiert.
- Eine SHA-256-Kennung über die kanonischen Auftragsfelder verhindert das
  doppelte Anlegen desselben logischen Auftrags.
- Erlaubte Übergänge sind ausschließlich
  `draft -> initiated -> challenge_received -> awaiting_user -> submitted`
  und anschließend `accepted`, `rejected` oder `unknown`.
- Terminale Zustände dürfen nicht zurück in einen Sendezustand wechseln;
  insbesondere ist aus `unknown` kein automatischer Retry erlaubt.
- Bei `accepted` entsteht innerhalb derselben SQLite-Transaktion höchstens
  eine vorgemerkte Buchung mit `payment:<Auftrags-UUID>` als Herkunft.
- Der UI-Stand ist deutlich als Simulator ohne echte Bankverbindung
  gekennzeichnet und fordert vor der Initialisierung eine zweite
  Bestätigung anhand einer unveränderlichen Zusammenfassung.
- Erlaube die vollständige Korrektur eines einzelnen Auftrags ausschließlich
  im Zustand `draft` und solange er keinem Sammler angehört. Prüfe dabei das
  offene EUR-Auftraggeberkonto, die Währungsidentität, Empfänger- und
  Bankverknüpfung, IBAN, optionale BIC, SEPA-Feldlängen und Betrag erneut.
  Berechne die SHA-256-Idempotenzkennung aus den geänderten kanonischen
  Auftragsfeldern neu und weise eine Kollision mit jedem anderen Auftrag ab.
  Bewahre UUID, Erstellungszeit und Status, erhöhe die Version und schreibe
  die Änderung atomar mit einem Auditereignis. Ab `initiated` sowie für
  Sammlermitglieder bleibt der Schnappschuss unveränderlich.
- Biete für freie Entwürfe und den Zustand `awaiting_user` einen ausdrücklich
  bestätigten Übergang nach `cancelled`. Abbrechen löscht weder Auftrag noch
  Auditverlauf und erzeugt keine Buchung; ein abgebrochener Auftrag kann
  weder bearbeitet noch erneut übermittelt werden.
- Exportiere einen ausgewählten Überweisungsauftrag lokal als
  `pain.001.001.09`. Kapsle die zeitabhängigen Regeln in
  `Pain001RulePackage.epc2025` mit Kennung `EPC-SCT-2025-V1.0`,
  Gültigkeitsbeginn 05.10.2025, Namespace und Quellenbezeichnung; streue
  Versionswerte nicht in UI oder Domänenmodell.
- Prüfe vor dem Export Auftrag/Konto-Zuordnung, Auftraggebername und -IBAN,
  ausschließlich EUR, positiven pain-Wertebereich, BIC mit 8 oder 11
  Zeichen, Namen/Verwendungszweck bis 140 Zeichen und Identifikatoren bis
  35 Zeichen. Identifikatoren dürfen nicht mit `/` beginnen oder enden und
  kein `//` enthalten.
- Schreibe `NbOfTxs` und `CtrlSum` auf Gruppen- und Zahlungsblockebene,
  `TRF`, `SEPA`, `SLEV`, `<ReqdExctnDt><Dt>…`, Konten als IBAN und den
  Betrag aus Minor-Units mit exakt zwei Dezimalstellen. Für
  Echtzeitüberweisungen ist `LclInstrm/INST` Pflicht.
- Hat das Auftraggeberkonto keine BIC, schreibe unter `DbtrAgt` die
  Kennung `NOTPROVIDED`. Fehlt die optionale Empfänger-BIC, lasse
  `CdtrAgt` vollständig weg. XML-Inhalte müssen UTF-8-codiert und sicher
  escaped werden.
- Der Export öffnet einen lokalen Dateidialog, sendet nichts an eine Bank
  und verändert weder Auftrag noch Buchungen. Prüfe deterministische
  Ausgabe, XML-Escaping, EPC-Kernelemente, Negativfälle und zusätzlich die
  generische Schema-Konformität mit einem `pain.001.001.09`-XSD.
- Erlaube diesen Initiierungsexport ausschließlich im Zustand `draft` und
  mit einem nicht geschlossenen Auftraggeberkonto. Ein bereits
  initialisierter, übermittelter, angenommener, abgelehnter oder unbekannter
  Auftrag darf dadurch niemals als vermeintlicher Retry exportiert werden.
- Speichere Dauerauftragsvorlagen ab Migration 14 getrennt von
  `payment_orders`. Pflichtfelder sind offenes EUR-Auftraggeberkonto, Name,
  Empfänger, gültige IBAN, optional gültige BIC, positiver Betrag,
  Verwendungszweck, nächste Fälligkeit, Frequenz und Wochenendregel.
- Status sind `active`, `paused` und terminal `cancelled`. Ein beendeter
  Dauerauftrag darf nicht reaktiviert werden. Bearbeitungen wirken nur auf
  offene künftige Fälligkeiten und dürfen das Datum nicht hinter die letzte
  verarbeitete Instanz zurücksetzen.
- Materialisiere eine Fälligkeit atomar als `scheduledCreditTransfer` im
  Zustand `draft`, Historienzeile und Fortschreibung des nächsten Termins.
  Der Idempotenzschlüssel lautet
  `standing:<Dauerauftrags-UUID>:<yyyy-MM-dd>`. Ein Retry derselben
  Fälligkeit liefert denselben Auftrag statt eines zweiten.
- Überspringen erzeugt eine terminale Historienzeile ohne Zahlungsauftrag.
  Materialisierte und übersprungene Instanzen dürfen nicht umgedeutet
  werden. Migration 29 speichert pro Vorlage ein unveränderlich benanntes
  Bankkalenderprofil und pro Historienzeile dessen Kennung und Version.
  `target-euro-v1` schließt neben Wochenenden den 1. Januar, Karfreitag,
  Ostermontag, 1. Mai sowie 25. und 26. Dezember; `weekdays-v1` erhält das
  frühere reine Montag-bis-Freitag-Verhalten. Verschiebe je nach Auswahl auf
  den nächsten oder vorherigen Bankarbeitstag oder gar nicht. Berechne Ostern
  deterministisch gregorianisch; spätere Regeländerungen benötigen eine neue
  Profilkennung. Zeige TARGET-Schließtage auch im Überweisungs- und
  Lastschriftentwurf an, behandle Echtzeitüberweisungen aber ausdrücklich als
  24/7-Verfahren. Quelle sind der TARGET-Betriebskalender der EZB und das
  Merkblatt zum unbaren Zahlungsverkehr der Deutschen Bundesbank.
- Der XCTest-Apphost muss eine pro Prozess temporäre Finanzdatei öffnen.
  Automatisierte Tests dürfen die Produktivdatei weder migrieren noch
  verändern; prüfe dies zusätzlich durch identische SHA-256-Werte vor und
  nach der vollständigen Suite.

Für die Berichtswerkstatt gilt zusätzlich:

- Definiere einen reinen, testbaren Katalog aus acht buchungsbasierten
  Standardberichten: Einnahmen/Ausgaben nach Kategorie, Einnahmen/Ausgaben
  nach Empfänger, Buchungsbericht, Cashflow nach Konto/Kategorie,
  Kontobewegungen nach Konto/Empfänger, Kategorie/Klasse, monatlicher Cashflow
  sowie deutscher Steuerbericht. Jede Definition
  liefert für das aktuelle lokale Kalenderjahr eine vollständige
  `TransactionReportQuery`; Jahresgrenzen müssen mit dem übergebenen Kalender
  und dessen Zeitzone berechnet werden.
- Das UI-Menü `Standardberichte` wendet eine Definition auf alle sichtbaren
  Filter an, zeigt Titel und Kurzbeschreibung und lässt danach jede Einstellung
  weiter bearbeiten. CSV, PDF und direkter Druck verwenden den aktiven
  Standardberichtstitel. Ein Standardbericht kann als normale versionierte
  Vorlage gespeichert werden. Budgetabweichung und Zeitvergleich dürfen erst
  als Standardbericht gelten, wenn ihre eigene Vergleichslogik implementiert
  und getestet ist.
- Implementiere `Kontosalden und Nettovermögen` als eigenständigen
  Stichtagsbericht. Normalisiere den gewählten Tag auf sein lokales Tagesende,
  berücksichtige den Eröffnungssaldo erst ab dem Eröffnungsdatum und addiere
  nur nicht stornierte, kontowährungsgleiche Buchungen vom Eröffnungsdatum bis
  zum Stichtag. Filtere Konten, Kontengruppen, Währungen sowie optional
  ausgeblendete, geschlossene und vom Nettovermögen ausgeschlossene Konten.
  Zeige je Konto Eröffnung, Bewegungen und Saldo. Summiere positive Salden als
  Aktiva, den Betrag negativer Salden als Passiva und den vorzeichenrichtigen
  Rest als Nettovermögen; verschiedene Währungen dürfen nie addiert werden.
  Erzeuge Bildschirmtabelle, deterministisches Semikolon-CSV, mehrseitiges
  A4-PDF in beiden Ausrichtungen und direkten Systemdruck aus genau demselben
  unveränderlichen Snapshot.
- Implementiere einen eigenständigen `PeriodComparisonEngine`. Berechne für
  zwei inklusive Datumsintervalle Einnahmen, Ausgaben oder Saldo mit der
  vorhandenen splitkorrekten Buchungsfakten-Pipeline. Erlaube Gruppierung nach
  Kategorie, Empfänger, Konto, Klasse/Tag oder keine Gruppierung. Richte
  Gruppen stabil nach Bezeichnung und Währung aus, auch wenn sie nur in einem
  Zeitraum vorkommen. Der Referenzwert ist wahlweise die Gesamtsumme oder der
  durch die Anzahl berührter Kalendermonate geteilte Monatsdurchschnitt.
  Zeige aktuellen Wert, Referenz, Differenz und auf Basispunkte gerundete
  prozentuale Änderung; bei Referenz null bleibt der Prozentsatz leer. Halte
  getrennte Fakten-IDs für den Drill-down beider Zeiträume und bilde
  Gesamtsummen ausschließlich je Währung.
- Implementiere einen eigenständigen `BudgetReportEngine`. Ein Bericht umfasst
  wahlweise alle zwölf Monate des frei beginnenden Geschäftsjahres oder einen
  ausgewählten Monat. Werte nur offene Konten in der Budgetwährung mit
  `includeBudget = true` aus, ignoriere Stornos und Umbuchungen und expandiere
  Splits ohne Doppelzählung. Verwende nur direkte Kategorieanteile, damit
  Elternkategorien nicht zusätzlich summiert werden. Zeige den vollständigen
  Kategoriepfad, Einnahme/Ausgabe, Basisplan, eingehenden Übertrag, wirksamen
  Plan, Ist, Abweichung und Zielerreichung. Plan und Ist sind fachlich positive
  Beträge; verwende dieselbe Saldoformel wie in der Budgetplanung und gib die
  ausgehende Roll-over-Reserve des Berichtszeitraums gesondert aus.
  Optional bleiben leere Plan-/Ist-Zeilen sichtbar. Drill-down-IDs dürfen nur
  die jeweilige Kategoriezeile enthalten.
- Zeit- und Budgetvergleich erzeugen deterministisches Semikolon-CSV,
  mehrseitiges A4-PDF in beiden Ausrichtungen und direkten Systemdruck aus
  demselben Snapshot. CSV und PDF enthalten währungsgetrennte Gesamtsummen;
  die Oberfläche darf keine neue Berechnung für den Export durchführen.
- Erlaube neben der Primärgruppierung optional eine davon abweichende zweite
  Dimension aus Kategorie, Empfänger, Konto und Klasse/Tag. `Keine
  Gruppierung` bleibt nur als ausgeschaltete Sekundärdimension beziehungsweise
  als vollständig ungruppierte Primäransicht zulässig. Erzeuge stabile
  kombinierte Gruppenkennungen und sichtbare Labels `Primär › Sekundär`, ohne
  Währungen zusammenzurechnen. Drill-down, CSV, PDF und Druck müssen dieselbe
  Gruppenmenge verwenden.
- Speichere die Sekundärdimension in Berichtsvorlagen ab Definitionsversion 2.
  Das Feld ist optional zu codieren, damit Vorlagen der Version 1 ohne dieses
  JSON-Feld weiterhin als eindimensionale Auswertung lesbar bleiben.
- PDF-Export und direkter Systemdruck müssen denselben unveränderlichen
  `TransactionReportSnapshot`, dieselben Filtermetadaten und dieselbe gewählte
  Hoch-/Querformatausrichtung verwenden. Erzeuge den PDF-Datenstrom genau
  einmal über `TransactionReportPDFExporter`; der Druckpfad darf keine zweite
  fachliche Auswertung oder abweichende Seitengestaltung besitzen.
- Öffne den macOS-Druckdialog erst nach ausdrücklichem Klick auf `Drucken …`.
  Der Vorgang verändert weder Buchungen noch Berichtsvorlagen.

Für SEPA-Core-Lastschriften gilt reproduzierbar:

- Migration 24 erzeugt `direct_debit_orders`. Ein Auftrag referenziert ein
  offenes EUR-Gläubigerkonto, einen aktiven Empfänger, genau dessen aktive
  Bankverbindung und genau dessen aktives unterschriebenes Mandat.
- Friere beim Anlegen Gläubigername/-ID/IBAN/BIC, Schuldnername/-IBAN/BIC,
  Mandatsreferenz/-datum/-sequenz, Betrag, Fälligkeit, Verwendungszweck und
  End-to-End-ID als unveränderlichen Schnappschuss ein. Prüfe die exakte
  Übereinstimmung mit den Stammdaten innerhalb derselben SQLite-Transaktion.
- Verwende dieselbe sichere Zustandsmaschine wie bei Überweisungen. Eine
  Annahme materialisiert atomar genau eine positive vorgemerkte Buchung mit
  stabiler Kennung `direct-debit:<Auftrags-UUID>`. TAN/Freigabecode bleiben
  ausschließlich kurzlebiger UI-Zustand.
- Prüfe beim Anlegen zusätzlich Namen und Verwendungszweck bis 140 Zeichen,
  End-to-End-ID und Mandatsreferenz bis 35 Zeichen, beide optionalen BICs und
  die SEPA-Slashregeln. Biete für `draft` und `awaiting_user` einen getrennt
  bestätigten Abbruch nach `cancelled`; der Schnappschuss bleibt unverändert,
  wird nicht gelöscht und materialisiert keine Buchung.
- Exportiere nur Entwürfe lokal als `pain.008.001.08`. Kapsle Namespace,
  Wirksamkeit ab 05.10.2025 und Quellenkennung in
  `Pain008RulePackage.epc2025` (`EPC-SDD-CORE-2025-V1.1`). Schreibe CORE,
  Sequenztyp, Fälligkeit, Kontrollsummen, Gläubiger-ID, Mandat und sämtliche
  Schuldnerdaten; validiere EUR, Betrags-/Längen-/Slash-/BIC-Regeln und
  XML-Escaping. Der Export sendet nichts und ändert keinen Auftrag.
- Zeige im Zahlungsverkehr getrennte Segmente für Überweisungen,
  Lastschriften und Daueraufträge. Vor Ausführung muss die vollständige,
  unveränderliche Lastschriftzusammenfassung sichtbar und doppelt bestätigt
  sein. Prüfe Rundlauf, Manipulationsschutz, Idempotenz, Zustandsübergänge,
  genau-einmalige Buchung und deterministischen XML-Export.

Für Sammelüberweisungen und Sammellastschriften gilt reproduzierbar:

- Migration 25 erzeugt `payment_batches` und `payment_batch_items`. Ein
  Sammler besitzt Art, Namen, gemeinsames Konto und Datum, Status,
  Idempotenzkennung, geordnete unveränderliche Mitglieder und Zeitstempel.
  Derselbe Einzelauftrag darf durch partielle Unique-Indizes höchstens einem
  Sammler angehören.
- Erlaube nur mindestens zwei freie Entwürfe. Sammelüberweisungen müssen
  offenes EUR-Konto, Auftragstyp und Ausführungstag teilen;
  Sammellastschriften zusätzlich Fälligkeit, Sequenztyp und den vollständigen
  Gläubigerschnappschuss. Prüfe diese Invarianten vor und erneut innerhalb
  derselben SQLite-Transaktion. Summiere ausschließlich überlaufgeschützt in
  Minor-Units und beachte den pain-Höchstbetrag.
- Bewege Sammler und sämtliche Mitglieder atomar durch dieselbe strikte
  Zahlungszustandsmaschine. Sperre individuelle Statusaktionen für gebündelte
  Mitglieder. Bei Annahme entstehen pro Mitglied genau einmal vorgemerkte
  Buchungen mit `payment:<UUID>` beziehungsweise `direct-debit:<UUID>`;
  Teilzustände und Teilbuchungen sind unzulässig.
- Biete in `draft` und `awaiting_user` einen ausdrücklich bestätigten Abbruch
  des gesamten Sammlers. Sammler und sämtliche Mitglieder müssen innerhalb
  derselben SQLite-Transaktion nach `cancelled` wechseln; kein Mitglied darf
  gelöscht, einzeln weitergeschaltet oder als Buchung materialisiert werden.
- Zeige im vierten Zahlungsverkehrssegment Art, Anzahl, Gesamtsumme, Konto,
  Termin, unveränderliche geordnete Positionen und Statuspfad. Verlange vor
  der Simulation Zusammenfassungs- und Ausführungsbestätigung; ein
  Freigabecode bleibt flüchtiger UI-Zustand. Aus `unknown` erfolgt kein
  automatischer Retry.
- Exportiere ausschließlich Sammler im Entwurfszustand als ein gemeinsames
  `pain.001.001.09` oder `pain.008.001.08`. Prüfe exakte Mitgliedschaft und
  Reihenfolge, gemeinsame Invarianten sowie jeden Schnappschuss. Schreibe
  `BtchBookg=true`, Anzahl und Kontrollsumme auf Gruppen- und
  Zahlungsblockebene sowie je Mitglied genau einen Transaktionsblock.
  Einzel- und Sammelexport sind deterministisch, XML-escaped, lokal und
  verändern weder Status noch Buchungen.
- Prüfe beide Sammlerarten als Datenbank-Rundlauf einschließlich
  Deduplizierung, Schutz individueller Mitglieder, aller Zustandsübergänge,
  genau-einmaliger Buchung, deterministischem Mehrpositions-XML,
  Migration 14→29 und Migration 22→29.

Für eingehende Zahlungsstatusberichte gilt reproduzierbar:

- Migration 26 erzeugt `payment_status_reports` und
  `payment_status_report_items`. Der Bericht speichert SHA-256-Fingerabdruck,
  Finanzdatei, Banknachrichtenkennung, Quell-/Importzeit, Positions-,
  Anwendungs- und Warnungszahl. Jede Position bewahrt Originalreferenzen,
  Zielart/-UUID/-titel, Bankstatus und -grund sowie vorherigen und tatsächlich
  angewandten lokalen Status unveränderlich auf.
- Akzeptiere ausschließlich höchstens 10 MB große `pain.002.001.10`-Dokumente
  im exakten ISO-Namespace und höchstens 20.000 Positionen. Verwirf DTD,
  ENTITY, externe Entitäten, falsche Namespaces und strukturell unvollständige
  Dokumente. Ein SHA-256-Fingerabdruck macht den Import dateiweit idempotent.
- Ordne ausschließlich über die vom eigenen Export erzeugten exakten
  Nachrichten-/Zahlungsblockkennungen und End-to-End-IDs zu. Eine
  Transaktionsreferenz darf nur ein einzelnes Mitglied treffen, niemals den
  Sammler selbst. Enthaltene Mitglieder sind nur informativ; der Sammler wird
  ausschließlich auf Gruppen- oder Zahlungsblockebene atomar bestätigt.
- Behandle `ACSC` als finale Annahme und `RJCT` als finale Ablehnung. Nur diese
  beiden Codes können einen lokalen Status ändern. `ACTC`, `ACCP`, `ACSP`,
  `PDNG`, `PART` und unbekannte Codes bleiben reine Historie und erzeugen
  keine Geldwirkung. Ein zuvor unklarer lokaler Status darf durch einen echten
  Bericht final aufgelöst werden, aber niemals automatisch erneut gesendet
  werden.
- Zeige vor dem Commit jede Position mit Originalreferenz, Bankstatus,
  Gründen, lokalem Ziel und Statuswechsel; nur anwendbare finale Positionen
  sind auswählbar. Verlange eine zweite Bestätigung. Berechne die Zuordnung im
  Commit erneut und lehne veraltete Vorschauen ab.
- Speichere Berichtshistorie, Statuswechsel und genau-einmalige Buchungen in
  derselben äußeren SQLite-Transaktion. Verschachtelte Store-Aktionen verwenden
  Savepoints. Bei einem Fehler werden Bericht, Status und Geldwirkung
  vollständig zurückgerollt. Eine `ACSC`-Bestätigung erzeugt höchstens die
  bereits domänenseitig definierte Buchung; `RJCT` erzeugt keine.
- Zeige im fünften Zahlungsverkehrssegment eine persistente Berichtsliste,
  vollständige Positionshistorie und einen sicheren XML-Dateiimport. Prüfe
  Parserhärtung, exakte Finalsemantik, atomare Einzel- und Sammlerverarbeitung,
  Deduplizierung, Migrationen und Datenbankintegrität automatisiert.

Für eingehende Überweisungs- und Lastschriftaufträge gilt reproduzierbar:

- Migration 27 erzeugt `payment_instruction_imports` und
  `payment_instruction_import_items`. Die Kopftabelle speichert
  SHA-256-Dateifingerabdruck, Nachrichtenart/-kennung, Quellzeitpunkt,
  Importzeitpunkt sowie Gesamt-, Übernahme-, Auslassungs- und Warnungszahl.
  Jede Position bewahrt Quelldatenkennung, Zahlungsblock, Reihenfolge,
  Ergebnis, Begründung und gegebenenfalls Zielart/-UUID unveränderlich.
- Akzeptiere ausschließlich höchstens 10 MB große Dokumente im exakten
  Namespace `pain.001.001.09` beziehungsweise `pain.008.001.08`, höchstens
  20.000 Positionen und keine DTD/ENTITY oder externen Entitäten. Prüfe
  Erstellungszeitpunkt, eindeutige Identifikatoren, SEPA-Servicelevel,
  Zahlungsart, EUR-Beträge in Minor Units, IBAN/BIC, Daten, CORE-Sequenz und
  Anzahl/Kontrollsumme auf Gruppen- und Blockebene.
- Ordne das lokale offene EUR-Konto ausschließlich über exakten Inhabernamen,
  IBAN und vorhandene Quell-BIC zu. Ordne eine aktive Empfängerbank ebenso
  exakt über Kontoinhaber, IBAN und Quell-BIC zu. Bei Lastschriften ist
  zusätzlich genau ein aktives Mandat derselben Akte mit identischer
  Referenz, Unterschrift und Sequenz Pflicht. Mehrdeutigkeit ist ein Fehler;
  Überweisungen ohne passende Empfängerakte dürfen als bewusst unverbundener
  Entwurf importiert werden.
- Die Vorschau ist unveränderlich, markiert nur importierbare Positionen
  standardmäßig und verlangt nach der Positionsauswahl eine zweite
  Bestätigung. Berechne sämtliche Zuordnungen direkt vor dem Commit erneut
  und lehne eine veraltete Vorschau vollständig ab.
- Speichere ausschließlich neue Überweisungs- oder Lastschriftentwürfe. Der
  Import sendet nichts, ändert keinen Auftragsstatus und erzeugt keine
  Buchung. Sind alle mindestens zwei Positionen eines Quellzahlungsblocks
  gewählt, rekonstruiere einen Sammler mit stabiler Quellenreihenfolge;
  Teilauswahlen bleiben Einzelentwürfe.
- Führe Entwürfe, Sammler, sämtliche Historienpositionen und Audit gemeinsam
  in einer äußeren SQLite-Transaktion aus. Stabile Positions-UUIDs und der
  Dateifingerabdruck verhindern Doppelübernahmen. Zeige im sechsten Segment
  `Dateiimporte` Importliste und vollständige Detailhistorie.
- Teste Export-Import-Rundläufe für beide Formate, DTD/ENTITY und falschen
  Namespace, manipulierte Kontrollsummen, exakte und veraltete
  Stammdatenzuordnung, Lastschriftmandate, Sammlerreihenfolge, Atomarität,
  Idempotenz, Migrationen und SQLite-Integrität ausschließlich synthetisch.

Für EPC-QR-Rechnungsdaten gilt reproduzierbar:

- Verwende das informative Rechnungsprofil EPC069-12 Version 3.1, nicht ein
  Point-of-Interaction-Verfahren. Lies genau einen QR-Code aus einer lokalen
  Bilddatei vollständig offline über Vision. Begrenze die Datei auf 20 MB und
  jede Bildkante auf 12.000 Pixel; kein oder mehrere QR-Codes sind Fehler.
- Akzeptiere ausschließlich Service-Tag `BCD`, Version `001` oder `002`,
  Zeichensatzkennung 1 bis 8 und Identifikation `SCT`. Rekonstruiere die
  deklarierte Codierung und weise Nutzlasten über 331 Byte ab. LF und CRLF
  sind zulässig, ein Trennzeichen nach dem letzten befüllten Feld nicht.
- Prüfe BIC-Pflicht in Version 001, BIC-Struktur, Empfängername bis 70,
  Mod-97-IBAN bis 34, optionalen Betrag `EUR0.01` bis `EUR999999999.99`,
  optionalen alphanumerischen Zweckcode bis vier Zeichen, strukturierte
  Referenz bis 35 oder alternativ Freitext bis 140 und Hinweis bis 70.
  Beginnt eine Referenz mit `RF`, muss ihre ISO-11649-Prüfsumme stimmen.
- Fülle Empfänger, Bankdaten, Betrag, Zweckcode, Referenz/Freitext und Hinweis
  ausschließlich in den vorhandenen sichtbaren Überweisungseditor. Speichere,
  sende und buche durch den Scan niemals automatisch. Verknüpfe eine aktive
  Empfängerbank nur bei genau einer exakten Namens-/IBAN-/BIC-Übereinstimmung.
- Migration 28 ergänzt `payment_orders.purpose_code` als leeren oder ein bis
  vier Zeichen langen Schnappschuss. Beziehe ihn in die Idempotenzkennung ein,
  zeige ihn im Detail und exportiere ihn optional als `Purp/Cd` in pain.001.
- Teste reinen Parser, Negativfälle, einen wirklich erzeugten und über Vision
  wieder gelesenen PNG-QR-Code, Schema-Rundlauf, Altmigrationen,
  pain.001-Export und SQLite-Integrität.

Für Empfänger und Klassen/Tags gilt reproduzierbar:

- `payees`, `payee_aliases`, `tags`, `transaction_tags` und `split_tags`
  werden ab SQLite-Migration 7 gespeichert.
- Der sichtbare Empfängertext bleibt für Importtreue erhalten; `payee_id`
  verknüpft optional die kanonische Empfängerakte.
- Aliase werden getrimmt, dedupliziert und getrennt vom kanonischen Namen
  gespeichert.
- Migration 22 ergänzt die normalisierte, mit dem SEPA-Mod-97-Verfahren
  geprüfte Gläubiger-ID, n:m-Standardklassen über `payee_default_tags` und
  mehrere `sepa_mandates` je Empfänger. Eine Mandatsreferenz ist je Empfänger
  eindeutig, 1 bis 35 zulässige SEPA-Zeichen lang und wird zusammen mit
  optionalem Unterschriftsdatum, Sequenztyp OOFF/FRST/RCUR/FNAL, Notiz und
  Aktivstatus atomar versioniert gespeichert.
- Migration 23 erzeugt `payee_bank_accounts`. Jede Empfängerakte kann mehrere
  eindeutig benannte Bankverbindungen mit Kontoinhaber, normalisierter und
  geprüfter IBAN, optionaler BIC, Bankname, Aktivstatus und Version führen.
  Ein partieller eindeutiger Index erlaubt höchstens eine aktive
  Standardverbindung je Empfänger. Beim Deaktivieren des Standards wird eine
  andere aktive Verbindung deterministisch hochgestuft. Vorhandene
  `payees.iban`-/`payees.bic`-Werte werden als `Standardkonto` übernommen.
- Ergänze `payment_orders` um optionale `payee_id` und
  `payee_bank_account_id`. Bei einer Aktenauswahl muss die Bankverbindung
  existieren, aktiv sein, zum Empfänger gehören und exakt den normalisierten
  IBAN-/BIC-Schnappschuss des Auftrags liefern. Speichere weiterhin Name,
  IBAN und BIC direkt im Auftrag, damit eine spätere Stammdatenänderung einen
  bestätigten Zahlungsentwurf niemals rückwirkend verändert. Manuelle
  Aufträge und historische Zeilen ohne Verknüpfung bleiben gültig.
- Tags besitzen optionale Hierarchie, Farbe, Beschreibung und Aktivstatus.
- Verhindere Selbstbezüge, fehlende Oberklassen und direkte oder indirekte
  Kreise vor jedem Speichern. Zeige auswählbare und zugeordnete Tags anhand
  des vollständigen Pfads `Oberklasse › Unterklasse`, sortiert nach Pfad.
- Hauptbuchungen und Splitzeilen besitzen unabhängige n:m-Tag-Zuordnungen.
- Einzel-, zweites und Sammelkontoblatt filtern unabhängig nach genau einer
  Klasse; dabei zählen Zuordnungen der Hauptbuchung und ihrer Splits. Der
  Filter ist Teil benannter Einzel- und Sammelansichten, alte JSON-Ansichten
  ohne `tagID` bleiben decodierbar. Filterleiste, Druck-/PDF-Beschreibung und
  Tabellenspalte verwenden den vollständigen Hierarchiepfad.
- SmartFill normalisiert Suche, Name und Aliase getrimmt sowie ohne
  Großschreibungs- und Diakritikaunterschiede. Es priorisiert Präfixtreffer
  vor bloßen Teiltreffern, dann die Anzahl bisheriger `payee_id`-Verwendungen,
  den normalisierten kanonischen Namen und zuletzt die UUID. Zeige den
  treffenden Alias und die Verwendung im Vorschlag. Erst eine bewusste
  Auswahl übernimmt den kanonischen Namen und noch freie Standardwerte im
  Editor, einschließlich Standardklasse/-tag. Weicht der Text danach vom Namen
  ab, löse `payee_id`, damit niemals eine falsche Empfängerakte gespeichert
  wird. Der Buchungseditor bietet für die gewählte Akte deren aktive Mandate
  an und persistiert Gläubiger-ID und Mandatsreferenz in der Buchung; genau ein
  aktives Mandat darf automatisch vorgeschlagen, niemals jedoch unbemerkt
  gespeichert werden.

Für Depots und Wertpapiere gilt reproduzierbar:

- Migration 8 speichert `securities`, `asset_classes`,
  `security_allocations`, `security_trades`, `portfolio_lots`,
  `lot_disposals` und `security_prices`.
- Stückzahlen sind `Int64`-Mikroeinheiten mit dem Faktor 1.000.000;
  Geld und Kurse bleiben `Int64`-Minor-Units.
- Jeder Kauf erzeugt atomar eine Transaktion und ein unveränderlich
  referenziertes Anschaffungslos.
- Verkäufe verbrauchen Lots nach Kaufdatum und UUID in FIFO-Reihenfolge.
  Teilverkäufe reduzieren Reststückzahl und Restkosten proportional; beim
  vollständigen Verbrauch wird die gesamte verbleibende Kostenbasis
  übernommen, damit keine Rundungsreste stehen bleiben.
- Vor dem Verkauf wird der Gesamtbestand geprüft. Bei Unterdeckung findet
  keinerlei Mutation statt; Short-Verkäufe bleiben im aktuellen UI
  deaktiviert.
- Realisierter Gewinn ist Nettoerlös nach Gebühren und Steuern abzüglich
  zugeordneter Kostenbasis. Unrealisierter Gewinn ist Marktwert zum letzten
  Kurs abzüglich verbleibender Kostenbasis.
- Vermögensklassen werden in Basispunkten gespeichert und nur atomar
  ersetzt, wenn ihre Summe exakt 10.000 (= 100 %) beträgt.

Für Kredite und Vermögenswerte gilt reproduzierbar:

- Migration 9 speichert `loans`, `loan_interest_rates`,
  `loan_extra_payments`, `loan_payment_matches`, `property_assets` und
  `asset_valuations`.
- Ein Darlehen besitzt Darlehensbetrag, Auszahlung, erste Fälligkeit,
  Laufzeit in Monaten, Monatsrate, regelmäßige Gebühr, Zinsbindung,
  Zahlungskonto, Notiz und Aktivstatus.
- Sollzinsen sind als ganzzahlige Basispunkte mit `effective_from`
  versioniert. Der Tilgungsplan wählt für jede Fälligkeit den zuletzt
  wirksamen Satz.
- Die Berechnung erfolgt mit `Decimal`, Rundung auf `Int64`-Minor-Units
  und einem gregorianischen UTC-Kalender. Damit verschiebt die Sommerzeit
  keine fachlichen Stichtage.
- Jede Planzeile weist Anfangssaldo, Rate, Tilgung, Zins, Gebühr,
  Sondertilgung und Endsaldo aus. Es gilt stets:
  `Summe(Tilgung + Sondertilgung) + Restschuld = Darlehensbetrag`.
- Eine Rate, die Zins und Gebühr nicht deckt, wird statt negativer
  Amortisation als ungültig abgewiesen.
- Vermögenswerte besitzen Typ, Kaufdatum, Kaufwert, Ort, Notiz und
  optional einen verknüpften Kredit. Datierte Bewertungen bilden den
  Wertverlauf; der Nettoanteil ist aktueller Wert minus Restschuld.
- Die Oberfläche schaltet zwischen Kredit- und Vermögenssicht um und zeigt
  aggregierte Vermögenswerte, Restschulden sowie den Nettoanteil.
- Ergänze einen eigenständigen `LoanReportEngine`. Eine Query filtert optional
  Zeitraum, Darlehens-UUIDs, Währungen und inaktive Darlehen. Der unveränderliche
  Snapshot enthält je Darlehen Originalbetrag, Perioden-Anfangssaldo,
  Zahlungen, Tilgung, Zinsen, Gebühren, Sondertilgungen, Perioden-Endsaldo,
  geplantes Ablösedatum und die referenzierten Planzeilen-IDs. Jede Zeilen-ID
  ist deterministisch aus Darlehens-UUID und Ratennummer aufgebaut.
- Das UI öffnet `Kredit-, Zins- und Tilgungsbericht …` im Menü
  `Standardberichte`, zeigt eine breite Darlehensübersicht und für die Auswahl
  den vollständigen Ratenplan sowie eine Restschuldlinie. Verschiedene
  Währungen bleiben in Ansicht und Summen strikt getrennt.
- Migration 37 erweitert `loan_payment_matches` um Sondertilgung, Herkunft
  sowie den JSON-Zustand vor und nach der Zuordnung. Fehlt die historische,
  bis dahin ungenutzte Tabelle in einer frühen Altdatei, wird sie defensiv
  rekonstruiert. Trigger blockieren Änderungen und Löschungen zugeordneter
  Buchungen außerhalb des dafür vorgesehenen Workflows.
- Für eine offene Planzeile bietet das UI negative, gebuchte, ungeteilte und
  noch nicht verwendete Belastungen des verknüpften Kontos in derselben
  Währung innerhalb von ±45 Tagen an. Exakte Beträge stehen vor Datumstreffern.
  Die Zuordnung zerlegt den tatsächlichen Betrag atomar in Sollzins, Gebühr,
  Tilgung und einen etwaigen Mehrbetrag als Sondertilgung. Unterdeckung von
  Zins und Gebühr sowie Übertilgung werden abgewiesen.
- Alternativ erzeugt `Planrate buchen` eine neue Splitbuchung. Jede Zuordnung
  ist je Transaktion und Planfälligkeit eindeutig. Beim Lösen wird eine
  generierte Buchung gelöscht oder eine vorhandene Buchung aus dem gespeicherten
  Original-JSON exakt wiederhergestellt; eine zwischenzeitlich abweichende
  Buchung wird nicht überschrieben.
- `LoanReportEngine` nimmt die Zahlungszuordnungen in denselben unveränderlichen
  Snapshot auf. UI, CSV, mehrseitiges A4-PDF und Systemdruck zeigen Plan, Ist,
  Abweichung, Herkunft und Anzahl abgeglichener Raten; Währungen bleiben strikt
  getrennt. Tests sichern zusätzlich reversible Splits, Datenbankschutz,
  Migration 36→37 und lückenhafte frühe Altdateien.
- Noch offen sind Kredit-Szenarien und der optionale Debt-Reduction-Planner.

Für die Vertrags- und Inventarübersicht gilt reproduzierbar:

- Implementiere genau einen unveränderlichen `AssetRegisterReportSnapshot`.
  Filtere Aktivstatus, Vertragstypen, Inventarkategorien,
  diakritikaunabhängigen Volltext sowie Kündigungs- und Garantiefristen für
  alle oder die nächsten 30/90/365 Tage.
- Vertragszeilen enthalten Anbieter, Vertragsnummer, Typ, Jahreskosten,
  nächste Verlängerung, Kündigungsfrist, Zahlungskonto und vollständigen
  Kategoriepfad. Inventarzeilen enthalten Kategorie, Raum, Kaufpreis,
  aktuellen Wert, Versicherungswert, Garantieende, Händler und Seriennummer.
- Zeige alle Summen und einen Zeilen-Drill-down. Deterministisches
  Semikolon-CSV, PDF in beiden Ausrichtungen und direkter Systemdruck nutzen
  denselben Snapshot und dieselben Filtermetadaten. Solange das Fachmodell
  keine Währung speichert, sind diese Werte ausdrücklich als EUR auszuweisen
  und dürfen nicht als Mehrwährungsbericht bezeichnet werden.

Für konfigurierbare Kontoblattansichten gilt reproduzierbar:

- Spalten besitzen stabile fachliche IDs und werden nicht über ihre
  lokalisierten Überschriften persistiert.
- Leere oder nicht dekodierbare Spaltenmengen fallen auf den vollständigen
  Standardsatz zurück; die Oberfläche verhindert, dass die letzte sichtbare
  Spalte entfernt wird.
- Konto- und Sammelkontoblatt lesen dieselbe Spalteneinstellung.
- Eine benannte Ansicht enthält Konto, Status, Kategorieauswahl, Zeitraum,
  benutzerdefinierte Datumsgrenzen, Zeilenmodus und sichtbare Spalten.
- Beim Laden werden externe UUID-Referenzen validiert. Ein nicht mehr
  vorhandenes Konto verändert das aktuelle Konto nicht; eine nicht mehr
  vorhandene Kategorie wird zu `Alle Kategorien`.
- Gleichnamiges Speichern aktualisiert statt eine schwer unterscheidbare
  Dublette anzulegen. JSON-Daten verwenden ISO-8601-Daten und sortierte
  Schlüssel für reproduzierbare Tests.
- Echte bedingte SwiftUI-Tabellenspalten benötigen macOS 14.4. Das Projekt
  setzt deshalb dieses Mindestziel für App und Tests konsistent.
- Speichere geöffnete Kontoblatt-Tabs als geordnete, deduplizierte Liste
  stabiler Konto-UUIDs. Beim Laden werden unbekannte Konten verworfen; die
  Reihenfolge der verbleibenden Tabs bleibt erhalten.
- Ein Wechsel aus der Kontenseitenleiste oder dem Kontopicker öffnet das
  Konto bei Bedarf als Tab. Beim Schließen des aktiven Tabs wird der
  unmittelbare Nachbar aktiv; nach dem letzten Tab fällt das Kontoblatt auf
  die kontenübergreifende Auswahl zurück.
- `⌘F` muss den echten Suchfokus setzen. `⌘S` wird über eine lokale
  Notification an den geöffneten Buchungseditor geroutet und speichert nur
  bei erfüllten Pflichtfeldern. `⌘⇧S` öffnet eine neue Splitbuchung oder
  aktiviert Splits im bereits geöffneten Editor. `⌘N` und `⌘R` bleiben
  globale Befehle für neue Buchung und Kontoabgleich.

## Freistellungsaufträge

Migration 36 erzeugt `tax_people`, `tax_allowance_rules`,
`tax_allowance_orders`, `tax_allowance_order_accounts` und
`tax_allowance_usages`. Eine Person speichert Name, Aktivstatus, nur die
letzten vier Ziffern der Steuer-ID und ein gesondertes
Steuer-ID-Bestätigungskennzeichen; die vollständige Steuer-ID darf in diesem
lokalen, noch unverschlüsselten Schema nicht persistiert werden.

Die Regelpakete sind zeitlich versioniert und enthalten für Einzel-/gemeinsame
Veranlagung 801/1.602 Euro von 2009 bis 2022 sowie 1.000/2.000 Euro ab 2023.
Quelle und amtliche URL zu § 20 Absatz 9 EStG werden mitgespeichert. Ein Auftrag
enthält Institut, Art, eine oder zwei verschiedene aktive Personen, Betrag,
Beginn, optionales Ende zum Kalenderjahresende, Notiz und Aktivstatus. Die
Kontoverknüpfungen dienen nur der Darstellung der institutsweiten Abdeckung;
sie dürfen den Auftrag fachlich niemals auf einzelne Konten oder Depots
beschränken und müssen zum selben normalisierten Institut gehören.

Validiere jeden Speichervorgang atomar gegen alle überlappenden Jahre.
Einzelaufträge derselben Person dürfen den Einzelrahmen nicht überschreiten.
Sobald ein gemeinsamer Rahmen besteht, zählen die Einzelaufträge beider
Partner zusammen mit allen gemeinsamen Aufträgen gegen dessen Höchstbetrag.
Eine Person darf in einem Jahr nicht mehreren unterschiedlichen gemeinsamen
Rahmen angehören. Die Jahresnutzung muss innerhalb der Gültigkeit liegen,
nicht negativ sein und darf weder den Auftragsbetrag überschreiten noch eine
spätere Herabsetzung unter den bereits genutzten Wert erlauben. Alle
Speicherpfade erzeugen Auditereignisse.

Die Oberfläche besitzt einen eigenen Seitenleisteneintrag und zusätzlich den
Eintrag `Freistellungsaufträge …` unter `Standardberichte`. Filtere nach
Steuerjahr, Person, Institut und Aktivstatus. Zeige Auftrag, Nutzung, Rest,
gesetzliches Maximum, Gültigkeit, Steuer-ID-Status und Kontenabdeckung sowie
zusammengefasste Personen-/Paarrahmen. CSV, mehrseitiges PDF und Systemdruck
müssen aus demselben unveränderlichen Snapshot entstehen. Weise sichtbar auf
die amtliche Rechtsgrundlage und darauf hin, dass es sich um eine
Verwaltungshilfe, nicht um Steuerberatung oder elektronische Auftragserteilung
an Banken handelt.

## Qualitätsschleife

### Reproduzierbarer PDF-Bericht

Erzeuge PDF niemals aus der gerade sichtbaren Tabelle, sondern aus demselben
unveränderlichen `TransactionReportSnapshot`, den Bildschirm und CSV
verwenden. `TransactionReportPDFExporter` rendert mit Core Graphics und
Core Text auf A4. Die Papiergröße ist 595,28 × 841,89 Punkt; im Querformat
werden Breite und Höhe vertauscht. Jede Seite besitzt feste Ränder, Titel,
Zeitraum, Abschnitt, wiederholten Tabellenkopf, Fußzeile und Seitenzahl.
Die erste Übersichtsseite enthält zusätzlich Basiswährung, Erstellungszeit
und die vollständig reproduzierbare Filterzusammenfassung. Gruppensummen und
Buchungsbeträge werden direkt aus `Int64`-Minor-Units deutsch formatiert;
Währungen bleiben getrennt.

Der Golden-Test erzeugt mindestens 80 Fakten und mehrere Gruppen, damit
Seitenumbrüche sicher ausgelöst werden. Er öffnet die Bytes mit PDFKit erneut
und prüft `%PDF`, Seitenzahl, Titel, Gruppen- und Buchungsabschnitt,
Kategoriepfad, Betrag und erste/letzte Seitenzahl. Für die visuelle Abnahme
das Ergebnis zusätzlich mit `pdfinfo` prüfen und mit `pdftoppm` mindestens
auf erster, mittlerer und letzter Seite als PNG rendern. Temporäre PDFs oder
gerenderte Seiten mit privaten Daten gehören ausschließlich in ignorierte
Build-Artefakte und niemals in Git.

Nach jedem vertikalen Schritt:

1. passende Unit- und Integrationstests ausführen; auf der aktuell
   verwendeten Xcode-Version bei Bedarf `XCT_DISABLE_SYMBOLICATION=1`
   setzen, damit eine fehlgeschlagene Assertion nicht in der
   Symbolizierung hängen bleibt,
2. Debug- und Release-Build kompilieren,
3. App öffnen und relevante Oberfläche prüfen,
4. `Gedächtnis.md` mit ausschließlich verifizierten Tatsachen aktualisieren,
5. Zwischenstand mit einem echten Screenshot im vereinbarten Telegram-Projektthread
   posten,
6. bekannte Abweichungen und nächsten kleinsten Schritt dokumentieren.

Fertig ist das Projekt erst, wenn die App lokal installiert und bedienbar ist,
die automatisierten Tests grün sind und alle verbleibenden Abweichungen zum
Master-Prompt transparent mit Schweregrad dokumentiert sind.

## Marken- und Kompatibilitätsregel

- Der Name der App lautet ausschließlich **FinanzVerwalter**.
- „Quicken“ darf nur dort vorkommen, wo ein sachlicher Hinweis auf ein
  tatsächlich unterstütztes Dateiformat oder einen notwendigen
  Kompatibilitätszweck erfolgt, beispielsweise „Import von Quicken-QIF-Dateien“.
- In unmittelbarer Nähe eines solchen Hinweises muss klar sein, dass
  FinanzVerwalter eine unabhängige, nicht autorisierte Neuentwicklung ist.
- Keine fremden Logos, Produktaufmachungen oder Herkunftshinweise übernehmen.
- Rechtsgrundlage als Arbeitsleitplanke ist § 23 Abs. 1 Nr. 3 in Verbindung
  mit Abs. 2 MarkenG; die Veröffentlichung bleibt einer menschlichen
  Rechtsprüfung vorbehalten.
# Reproduzierbarer Kontoblatt-Stand: Saldo, Ausgabe und F3

Das Kontoblatt besitzt elf dynamische Spalten. `balance` wird aus der
kontenweisen laufenden Saldenfolge der Buchungen befüllt, trägt den deutschen
Titel `Saldo` und steht in der Standardreihenfolge rechts von `Betrag`.
Bestehende Installationen benötigen eine einmalige, versionierte
Präferenzmigration: Sie ergänzt `balance` zu einer vorhandenen
`registerVisibleColumnsV1`-Liste sowie zu jeder benannten Ansicht und setzt
erst danach den Marker `registerVisibleColumnsIncludesBalanceV3`. Die neue
Markerversion behebt Bestandsinstallationen, bei denen ein früher gesetzter
Marker die Ergänzung einer später wiederhergestellten Altansicht verhindert
konnte.
Anschließend darf der Nutzer die Spalte wieder frei ausblenden.

Für Druck und PDF wird zuerst ein unveränderlicher `RegisterPrintSnapshot`
gebildet. Er enthält Titel, aktuelle Filterbeschreibung, Erstellungszeit,
die geordnete Liste der tatsächlich sichtbaren `RegisterColumn`-Werte und
pro sichtbarer Buchung genau eine gleich geordnete Textzeile. Der Renderer
skaliert nur diese Spalten auf A4 quer, wiederholt den Tabellenkopf auf jeder
Seite und schreibt `Seite x von y`. Derselbe PDF-Datenstrom geht entweder an
den nativen PDFKit-/AppKit-Druckdialog oder in einen SwiftUI-`fileExporter`.
Versteckte Spalten dürfen weder im Kopf noch in den Zeilen auftauchen.

Der F3-Workflow wird über den App-Befehl
`FinanzVerwalter.filterRegisterSelection` ausgelöst. Im Kontenblatt ist das
persistierte Zielfeld `registerF3FieldV1` zwischen Empfänger,
Verwendungszweck, Kategorie, Konto und Status wählbar. Genau eine markierte
Buchung wird über `RegisterF3Field.selection(for:)` in einen typisierten
Filterwert übersetzt. Keine oder mehrere Markierungen sowie leere Textfelder
ändern keinen Filter und melden den Grund in der Statuszeile.

# Reproduzierbare Kontoblatt-Accessibility und Tastaturkontexte

Vergib stabile Accessibility-Identifier für Kontoauswahl, Status-,
Kategorie- und Zeitraumfilter, Zeilenmodus, aktuellen Saldo sowie Haupt-,
zweite und Sammel-Buchungstabelle. Tabellen nennen sichtbar gefilterte und
ausgewählte Buchungszahlen. Jede dynamische Zelle erhält eine explizite
Beschriftung `Spaltentitel: Wert`; leere Werte werden als `Leer` gesprochen.
Kategorie und Saldo müssen den vollständigen sichtbaren Wert verwenden,
nicht den gekürzten Bildschirmtext.

Kontoblatt-Tabs bleiben als Container mit zwei getrennten Bedienelementen
zugänglich: Konto auswählen einschließlich Saldo/Auswahlstatus und genau
dieses Konto schließen. Kombiniere die Kinder nicht zu einem Element, weil
dadurch die Schließen-Aktion verloren gehen kann.

Der globale Kontextmonitor darf Löschen niemals während Texteingabe
verarbeiten. `Übernehmen` und `Abbrechen` dürfen nur bei tatsächlich
präsentiertem Sheet konsumiert werden; ohne Sheet müssen Eingabe und Escape
an Tabelle beziehungsweise normales AppKit-Key-Handling weiterlaufen. Teste
vollständigen Kategoriepfad, Saldo, Leerwert, Singular/Plural/Auswahl und die
Kontextentscheidung als reine deterministische Funktionen.

# Reproduzierbarer Kontoabgleich

Der Kontoabgleich darf niemals pauschal alle Buchungen bis zu einem Datum
ändern. Erzeuge einen unveränderlichen Abgleichskopf mit Konto,
Auszugsdatum, Anfangssaldo, markierter Summe, Endsaldo, Abschlusszeit,
optionaler Ausgleichsbuchung, Workflowversion und monotoner Folge. Halte jede
ausgewählte Buchung separat mit vorherigem Status, Betrag und
Ausgleichskennzeichen fest.

Der Anfangssaldo ist der Endsaldo des jüngsten aktiven Abgleichs oder ohne
Vorgänger der Eröffnungssaldo. Kandidaten sind ausschließlich gebuchte oder
bestätigte Buchungen desselben Kontos bis zum Stichtag. Nur explizit
markierte Kandidaten wechseln atomar zu `reconciled`. Eine Differenz bricht
ab, außer der Nutzer bestätigt in einem zweiten Schritt eine eigene
Ausgleichsbuchung mit Referenz `ABGLEICH`.

Nur der jüngste aktive Abgleich ist rücknehmbar. Stelle für normale
Positionen den gespeicherten vorherigen Status wieder her und setze eine
Ausgleichsbuchung auf `cancelled`, ohne sie zu löschen. Markiere den
Abgleichskopf als zurückgenommen und schreibe ein Auditereignis. Historische
Alteinträge ohne Positionsliste bleiben sichtbar, aber nicht rücknehmbar.

# Reproduzierbare Shortcuts und Buchungsvorlagen

Definiere zehn stabile Aktions-IDs für neue Buchung, Speichern, Suche,
Kontoabgleich, Splitdialog, Vorlage merken, F3-Filter, Löschen, Übernehmen
und Abbrechen. Speichere eine versionierte Liste aus Aktions-ID, Taste und
Menge der Modifikatoren. Ergänze bei alten Einstellungen nur fehlende
Aktions-IDs. Fällt JSON-Decodierung, Versionsprüfung, Eindeutigkeit oder
Sicherheitsprüfung aus, verwende vollständig die dokumentierten
Standardwerte.

Buchstaben, Ziffern und Leertaste ohne Modifikator sind unzulässig, weil sie
Texteingaben abfangen würden. Doppelte Kombinationen sind ebenfalls
unzulässig. Normale Aktionen können als dynamische macOS-Menübefehle
registriert werden. Behandle Löschen, Eingabe und Esc kontextabhängig:
Ein lokaler Key-down-Monitor darf Entfernen bei aktivem `NSTextView` niemals
abfangen. Erst außerhalb der Texteingabe wird eine typisierte
Anwendungsaktion ausgelöst.

Migration 17 erzeugt `transaction_templates` mit Finanzdatei-ID, eindeutigem
Namen, deterministisch codiertem JSON-Payload, Zeitstempeln und Version.
Der Payload enthält Konto, Empfänger, Zweck, Kategorie, Betrag, Währung,
normalisierten Status, Memo, Empfängerakte, Tags und sämtliche Splits samt
Split-Tags. Eine abgeglichene oder stornierte Quellbuchung wird als gebuchte
Vorlage gespeichert; eine einzelne Umbuchungsseite wird abgelehnt. Beim
Anwenden entstehen neue Buchungs- und Split-IDs sowie das heutige Datum;
Referenz, Transfer-ID und Importfingerprint bleiben leer.

Das Kontoblatt bietet zusätzlich `Als regelmäßigen Vorgang …`. Erzeuge daraus
über `ScheduledTransaction.draft(from:)` eine neue UUID, einen Namen aus
Empfänger oder Zweck, den nächsten heute oder künftig liegenden Monatstermin
mit erhaltener Monatsende-Semantik und Aktion `Nur erinnern`. Lehne eine
einzelne Umbuchungsseite ab. Der Serieneditor zeigt geerbte Splits und
Fremdwährung sichtbar an und sperrt den Betrag, solange Split-, MwSt.- oder
Fremdwährungsinvarianten davon abhängen. Kontowechsel sind nur innerhalb
derselben Währung zulässig. Der Store prüft offenes Konto, Kontowährung und
den vollständigen Payload erneut, bevor er atomar speichert und auditiert.

Vor dem Mehrfachlöschen müssen alle ausgewählten IDs existieren und alle
ausgewählten Buchungen sowie beide Seiten betroffener Umbuchungen
unangetastet sein. Enthält die Menge eine abgeglichene Buchung, ändere
nichts. Zeige immer eine Bestätigung mit der Zahl der Buchungen. Lösche
danach die gesamte validierte Menge in genau einer SQLite-Transaktion und
schreibe Auditereignisse.

# Reproduzierbarer Betragsrechner für manuelle Buchungen

Implementiere in `Money.swift` zusätzlich zum strikten Einzelwertparser einen
eigenen rekursiven Decimal-Ausdrucksparser. Er akzeptiert optional ein
führendes `=`, deutsche Zahlen mit Komma und korrekt gruppierten
Tausenderpunkten, Klammern, unäre Vorzeichen sowie `+`, `-`, `*`, `/` und die
Unicode-Zeichen `−`, `×`, `÷`. Punktrechnung hat Vorrang vor Strichrechnung.
Verwende weder `Double` noch `NSExpression`; führe jede Operation mit den
`NSDecimal...`-Funktionen und `.bankers` aus und runde erst das Gesamtergebnis
auf die Minor-Units der gewählten Währung.

Begrenze den Eingabetext auf 256 Zeichen, die Verschachtelung auf 32 Ebenen
und die Zahl der Operationen auf 128. Weise Division durch null, leere oder
unvollständige Ausdrücke, fehlerhafte Trennzeichen, arithmetischen Überlauf und
Ergebnisse außerhalb von `Int64` als normale ungültige Betragseingabe ab.
Der bisherige `Money(parsing:)`-Pfad bleibt ein strikter einzelner Zahlenwert
und darf keinen Ausdruck nur teilweise akzeptieren.

Verwende die Auswertung im manuellen Buchungsdialog für Hauptbetrag,
Fremdwährungs-Originalbetrag, jede Splitzeile und manuelle MwSt.-Beträge. Vor
dem Speichern normalisiere Haupt- und Originalbetrag auf deren
währungsabhängige `editingString`; die zentrale Store-Methode wertet dennoch
selbst aus, damit alle Aufrufer dieselbe Regel erhalten. Splitinvariante,
Vorzeichenregeln, Fremdwährungskurs und MwSt.-Rundung arbeiten anschließend
ausschließlich mit den ausgewerteten Minor-Units. Zeige die erlaubten
Operatoren am Betragsfeld als Hilfetext an.

# Reproduzierbare Mehrwertsteuer und Steuerzuordnung

Migration 18 erzeugt eine dateigebundene Tabelle `vat_codes` mit UUID,
Bezeichnung, Beschreibung, Satz in Basispunkten und Aktivstatus. Lege 0 %, 7 %
und 19 % als drei verschiedene Standarddatensätze an. Niemals darf ein
benutzerdefinierter 0-%-Schlüssel anhand seines Satzes auf den Standardschlüssel
umgebogen werden.

Erweitere Kategorien um Beschreibung, Budgetierbarkeit,
`defaultVATCodeID`, deutsche Steuerzuordnung und optionale US-Steuerzeile.
Normale Buchungen und jede Splitzeile erhalten `vatCodeID`, Modus `none`,
`automatic` oder `manual`, Netto-Cent und Steuer-Cent. Der vorhandene Betrag
ist brutto.

Berechne bei automatischer Bruttoeingabe mit `Decimal`:
`Steuer = Brutto × Basispunkte / (10_000 + Basispunkte)` und runde
kaufmännisch auf ganze Cent. Netto ist danach exakt Brutto minus Steuer. Bei
Splits muss diese Rundung separat je Zeile erfolgen; die Belegwerte sind die
Summe der bereits gerundeten Zeilen. Im manuellen Modus prüfe Vorzeichen,
Betragsgrenze und `Brutto = Netto + Steuer`. Alte Datensätze bleiben neutral
mit Modus `none` und Nullwerten.

Der Buchungsdialog schlägt den Kategorie-Standard vor, erlaubt die
Übersteuerung je Buchung beziehungsweise Splitzeile und zeigt Brutto, Netto
und Steuer vor dem Speichern. Die zweizeilige Kontenblattansicht nennt
Schlüssel, Netto und Steuer. Buchungsvorlagen müssen alle MwSt.-Felder
verlustfrei übernehmen.

Ergänze einen eigenständigen `VATReportEngine`. Seine Query filtert einen
freien Zeitraum, Konten und Kontengruppen, Status, Währungen, Umbuchungen sowie
ausgeblendete oder von Berichten ausgeschlossene Konten. Erzeuge Fakten immer
je tatsächlich gespeicherter MwSt.-Buchungs- oder Splitzeile; ein gemischter
Beleg darf nie über seine Belegsumme pauschalisiert werden. Gruppiere nach der
UUID des MwSt.-Schlüssels und Währung. Weise Zeilen anhand der Kategorieart der
Umsatzsteuer- oder Vorsteuerseite zu, nicht allein anhand des Vorzeichens:
Negative Einnahmen mindern die Umsatzsteuer, positive Ausgaben mindern die
Vorsteuer. Ohne Kategorieart ist nur ein dokumentierter Vorzeichen-Fallback
zulässig. Summiere Brutto, Netto, Umsatzsteuer, Brutto-/Nettoeinkauf,
Vorsteuer und Zahllast; verschiedene Währungen dürfen nie addiert werden.

Das UI öffnet den `Umsatzsteuerbericht` im Menü `Standardberichte`, bietet die
vollständigen Queryfilter, eine breite Schlüsselübersicht und einen
Buchungs-/Split-Drill-down mit vollständigem Kategoriepfad. Deterministisches
Semikolon-CSV enthält Übersicht, Währungssummen und Details. Mehrseitiges PDF
und Systemdruck verwenden denselben unveränderlichen Snapshot. Teste gemischte
7/19-%-Splits, Erlöse, Lieferantengutschriften, Kategoriepfade,
Währungstrennung, exakte Fakten-IDs, reproduzierbares CSV und semantisch
lesbares PDF.

# Reproduzierbares Import- und Bankumsatz-Matching

Migration 19 ergänzt jede Buchung um Herkunft (`manual`, `fileImport`,
`bankDownload`, `rule`, `scheduled`, `transfer`), externen Provider,
externe Transaktions-ID, Gegenkonto-IBAN, End-to-End-ID, Mandatsreferenz,
starken Dublettenfingerabdruck und optionalen Banksaldo nach der Buchung.
Erzwinge mit einem partiellen eindeutigen SQLite-Index, dass eine nicht leere
externe Transaktions-ID innerhalb von Konto und Provider nur einmal vorkommt.

Trenne Paket-Idempotenz und Buchungs-Matching. Der SHA-256-Hash der gesamten
Datei verhindert weiterhin die doppelte Übernahme genau desselben Pakets.
Daneben erzeugt jede Importvorschau pro Buchung maximal drei sortierte
Kandidaten desselben Kontos:

1. Exakte Provider- plus externe Transaktions-ID: Score 100, harter Treffer,
   standardmäßig überspringen.
2. Sonstige Kandidaten benötigen identischen Centbetrag und Währung sowie
   ein vom Nutzer zwischen 0 und 14 Tagen konfiguriertes Datumsfenster.
3. Ausgangsscore 45 für Betrag/Währung, bis zu 20 Punkte für Datum,
   20 für End-to-End-ID, 15 für Mandatsreferenz, 15 für Referenz, 15 für
   IBAN, 10 für identischen Empfänger sowie höchstens 8 beziehungsweise
   10 für tokenbasierte Ähnlichkeit von Empfänger und Zweck.

Zeige Kandidaten erst ab 55 Punkten. Schlage einen Merge nur bei mindestens
90 Punkten, finanzieller Kompatibilität und einem eindeutigen besten Score
vor. Bei Gleichstand oder schwächerem Ergebnis bleibt `Neu importieren`
voreingestellt. Die Tabelle muss je Importzeile `Neu importieren`,
`Überspringen` und jeden kompatiblen Kandidaten mit Empfänger, Datum, Betrag
und Score anbieten; Gründe stehen als Hilfe bereit. Eine Sammelaktion darf
weiche Treffer bewusst als neu markieren, harte externe IDs aber nicht
duplizieren.

Berechne beim Commit alle Kandidaten gegen den dann aktuellen Datenbestand
erneut. Lehne eine erzwungene neue Buchung mit bereits vorhandener harter
Bank-ID ab. Beim bestätigten Match bleiben lokale Kategorie, Memo, Splits,
Tags, Mehrwertsteuer und Transferstruktur erhalten. Ergänze Bankmetadaten,
setze erwartete oder vorgemerkte Umsätze auf gebucht und ändere bei bereits
abgeglichenen Buchungen keine geschützten fachlichen Felder. Schreibe für
Import, Überspringen und Merge nachvollziehbare Auditdaten.

# Reproduzierbare Regel-Engine und Undo-Pakete

Migration 20 ergänzt `categorization_rules.definition_json` sowie
`rule_application_runs` und `rule_application_items`. Ergänze Buchungen um
BIC, Gläubiger-ID und Buchungstext. Die Regeldefinition ist ein
versioniertes, mit sortierten JSON-Schlüsseln codiertes Datenmodell aus
einem rekursiven Ausdruck und einer geordneten Aktionsliste.

Ein Ausdruck ist entweder eine Bedingung oder eine Gruppe mit Logik `all`
(UND) beziehungsweise `any` (ODER) und beliebig vielen Kindausdrücken.
Bedingungen besitzen eine stabile UUID, Feld, Operator und bis zu zwei
Stringwerte. Unterstütze Empfänger/Auftraggeber, Zweck, IBAN, BIC, Betrag in
Cent, Vorzeichen, Konto-UUID, Buchungstext, Referenz, Mandatsreferenz,
Gläubiger-ID, End-to-End-ID, Buchungsdatum, Memo, Status und Herkunft.
Operatoren sind gleich, enthält, beginnt/endet mit, Regex, zwischen, leer und
nicht leer. Normalisiere Textvergleich ohne Beachtung von
Groß-/Kleinschreibung und Diakritika. Validiere Regex sowie Centbereiche vor
dem Speichern.

Aktionen sind typisierte Enum-Werte: Kategorie setzen, Empfänger
normalisieren, Memo setzen, Tags ergänzen, Zwecktext literal oder per Regex
ersetzen, Zweck in Memo kopieren sowie einen Einzeilen-Split über exakt den
Gesamtbetrag erzeugen. Verweigere widersprüchliche Mehrfachaktionen auf
dasselbe Zielfeld. Regeln ändern niemals Betrag, Konto, Status,
Transferidentität oder Abgleichstatus. Schließe abgeglichene, stornierte und
Transferbuchungen aus; Split-Erzeugung ist nur aus einer ungeteilten
steuerneutralen Buchung zulässig.

Sortiere Vorschauzeilen deterministisch nach Datum und UUID. Zeige je
Buchung alle geänderten Felder als Vorher/Nachher und lasse den Nutzer die
anzuwendenden UUIDs ausdrücklich auswählen. Prüfe die vollständige Auswahl
direkt vor dem Commit erneut. Speichere in derselben SQLite-Transaktion einen
vollständigen vorherigen JSON-Snapshot und den SHA-256-Fingerabdruck des
Nachher-Zustands.

Ein Undo-Paket darf nur einmal und nur vollständig angewandt werden.
Vergleiche vor jeder Rücknahme alle aktuellen Buchungsfingerabdrücke mit den
gespeicherten Nachher-Werten. Fehlt oder unterscheidet sich eine Buchung,
brich die gesamte Transaktion ab. Andernfalls schreibe alle Vorher-Snapshots
zurück, markiere den Lauf als zurückgenommen und auditiere ihn.

Für Konflikte ermittle alle aktiven Regeln in Prioritäts-/UUID-Reihenfolge.
Wenn dieselbe Buchung von mehreren Regeln für dasselbe Zielfeld
unterschiedliche Aktionen erhält, zeige Buchung, Zielfeld und Regelnamen.
Eine aus dem Kontoblatt erzeugte Regel verwendet Konto plus Empfänger
beziehungsweise Zweck als Bedingungen und die vorhandene Kategorie als
Aktion; sie wird nur gespeichert und nicht automatisch angewandt.

# Reproduzierbarer Read-only-Banking-Abruf

Migration 21 ergänzt dateigebundene Tabellen für Verbindungen,
Kontenzuordnungen, Abrufläufe und schreibgeschützt geladene Dauerauftrags-
beziehungsweise Terminüberweisungsbestände. Definiere einen
`ReadOnlyBankingAdapter`, der weder Repository noch SQLite kennt und ein
normalisiertes Paket aus Adapter-/Providerkennung, Abrufzeit, Rohdatenhash,
Konten, Salden, Umsätzen, Beständen und Diagnose je Konto/Vorgang liefert.

Implementiere zuerst ausschließlich einen lokalen, deterministischen
Simulator ohne Zugangsdaten. Er unterstützt Kontenliste, Salden, gebuchte
Umsätze, Vormerkposten, Dauerauftragsbestand und Terminüberweisungen.
Depotbestände und Kurse dürfen nicht als unterstützt erscheinen. Modellierte
FinTS-, PSD2-/Open-Banking- und Web-Provider bleiben in Oberfläche und
Persistenz deaktiviert, bis Providerzulassung, Lizenz, SCA, Consent,
Geheimnisspeicher, Datenschutz und Logging-Redaktion separat umgesetzt sind.

Ordne jedes ausgewählte externe Konto genau einem lokalen Konto gleicher
Währung zu. Die Normalisierung erzeugt aus Verbindung plus externer ID eine
stabile Buchungs-UUID, setzt Herkunft `bankDownload`, Provider und externe
Transaktions-ID und übernimmt IBAN, BIC, End-to-End-ID, Mandatsreferenz,
Gläubiger-ID, Buchungstext sowie optionalen Banksaldo. Wende alle passenden
Regeln in Prioritäts-/UUID-Reihenfolge an. Bei einem Zielfeldkonflikt wende
für diese Buchung keine Regel automatisch an und zeige den Hinweis. Zeige
ansonsten alle angewandten Regeln in der Abrufvorschau.

Ein konto- oder gruppenbezogener Einstieg darf diese Auswahl nicht wieder
durch alle aktiven Zuordnungen der Verbindung ersetzen. Existiert keine
passende aktive Zuordnung, bleibt die temporäre Abrufauswahl leer; der Nutzer
erhält den sichtbaren Zuordnungshinweis und kann keinen unbeabsichtigten
Fremdkontoabruf starten.

Führe danach das gleiche gestufte Import-Matching wie beim Dateiimport aus.
Die Vorschau zeigt Konten, Salden, Umsätze, Status, Regeln, konkrete
Importentscheidung, Bestände, Nutzermeldung, technischen Code und
SHA-256-Rohhash. Ein Abbruch darf keine Datenbankänderung auslösen.

Beim bestätigten Commit werden Adapterkennung, erfolgreiche Diagnosen,
eindeutige Zuordnungen, Währungen und Importentscheidungen erneut geprüft.
Schreibe neue/abgeglichene Buchungen, lokale Banksalden und Syncstatus,
Bestände, einen vollständigen Abruflauf und Auditdaten gemeinsam in genau
einer SQLite-Transaktion. Wiederholt sich derselbe Pakethash, sind nur
Skip-Entscheidungen zulässig. Speichere niemals Rohantworten, PIN, TAN,
Freigabecodes oder andere Bankgeheimnisse.

# Reproduzierbarer Kontoblatt-Minireport und geteilte Ansicht

Ergänze im normalen Kontoblatt einen ein-/ausblendbaren rechten Minireport.
Er folgt nur dann einer Buchung, wenn genau eine Zeile markiert ist. Die
Dimension ist zwischen Empfänger, Kategorie und Klasse/Tag umschaltbar. Für
Empfänger vergleiche getrimmt, ohne Groß-/Kleinschreibung und ohne
Diakritika. Für Kategorie und Tag verwende bei einer Splitbuchung nur die
Summe der passenden Splitzeilen; eine direkt am Hauptsatz gesetzte Kategorie
oder ein Haupt-Tag verwendet den Gesamtbetrag. Stornierte Buchungen zählen
nicht. Addiere verschiedene Währungen niemals: Zeige pro Währung Anzahl,
Einnahmen, Ausgaben, Saldo und die letzten acht Buchungen. Kategoriepfade
und Namen erscheinen vollständig im Tooltip.

Ergänze daneben eine persistierbar ein-/ausblendbare Zwei-Konten-Ansicht.
Das zweite Kontoblatt darf nicht dasselbe Konto wie das Hauptkontenblatt
verwenden und wählt nach Löschung oder Primärkontowechsel deterministisch ein
anderes offenes Konto. Es besitzt eigene Status-, Kategorie- und
Zeitraumfilter, übernimmt nur die globale Volltextsuche und zeigt mindestens
Datum, Empfänger/Zweck, vollständige Kategorie, Betrag und kontenweisen
laufenden Saldo. Ein Doppelklick öffnet denselben sicheren Buchungseditor.

Minireport und zweites Kontoblatt sind bei kleiner Fensterbreite nicht
gleichzeitig geöffnet: Das Aktivieren des einen blendet das andere aus.
Beide Zustände und die sekundäre Konto-ID liegen nur in lokalen
Benutzereinstellungen, nicht in der Finanzdatei. Teste die Minireport-
Splitbeiträge, Währungstrennung, Stornoausschluss sowie die unabhängige
Konto-/Status-/Kategorie-/Textfilterung als reine deterministische Logik.

# Reproduzierbare globale Kontenblatt-Volltextsuche

Erzeuge beim Laden der Finanzdatei genau einen unveränderlichen Suchindex für
alle persistenten Buchungen. Ein Dokument enthält sämtliche Kontofelder
einschließlich Institut, Typ, Gruppe, IBAN/BIC, Kontonummer, Inhaber,
Eröffnungsbetrag, Kreditlimit, Banksaldo und Synchronisationsstatus; außerdem
alle Buchungsfelder, vollständige Kategorie- und Klassenpfade aller Splits,
Status, Buchungs- und Wertstellungstag, Betrag, Netto, Steuer, laufenden Saldo,
Fremdwährungswerte und Bankreferenzen. Prognosezeilen erhalten dasselbe
Dokument flüchtig und werden nicht persistiert.

Normalisiere groß-/kleinschreibungs- und diakritikaunabhängig auf
alphanumerische Tokens. Alle eingegebenen Tokens müssen irgendwo im Dokument
vorkommen und dürfen aus verschiedenen Feldern stammen. Wortteiltreffer müssen
erhalten bleiben. Indexiere dafür ein-, zwei- und dreistellige Zeichenfragmente,
schneide die Kandidatenmenge über die Fragmente und verifiziere zuletzt am
normalisierten Gesamtdokument, damit keine Trigramm-Scheinmatches entstehen.
Einzelkonto, zweites Kontoblatt sowie beide Sammelansichten verwenden exakt
dieselbe Abfrage und dieselbe globale Suche.

Teste Konto-/Institutsfeld, vollständige Kategorie und Klasse, Status, Datum,
formatierten Betrag, laufenden Saldo, IBAN und Bankreferenz, kombinierte Tokens
aus mehreren Feldern, Diakritika und einen inneren Wortteil. Miss nur die
Nutzerabfrage gegen 100.000 bereits indexierte Dokumente; sie muss auf dem
Testsystem in weniger als 100 ms antworten.

# Reproduzierbarer Sammelkontoblatt-Ausbau

Das Sammelkontoblatt kombiniert eine frei wählbare Teilmenge aller offenen
Konten. Eine leere gespeicherte Kontenmenge bedeutet stabil „alle offenen
Konten“. Ergänze unabhängige Status-, vollständige Kategorie-, Zeitraum- und
Volltextfilter. Der Textfilter durchsucht Empfänger, Zweck, Memo, Referenz
und vollständigen Kategoriepfad. Sortiere immer chronologisch nach Datum und
UUID, niemals nach Abgleichstatus.

Ein eigener Schalter ergänzt regelmäßige Vorgänge für 365 Tage über dieselbe
deterministische Occurrence-Logik der Prognose. Berechne für reale und
errechnete Zeilen den laufenden Saldo getrennt je Ursprungskonto, beginnend
beim Eröffnungssaldo; Stornos verändern ihn nicht. Kennzeichne die erste
Zukunftszeile blau. Ein Filter verändert nie diesen echten kontenweisen
Saldo. Die Kopfsumme ist dagegen eine währungsgetrennte Bewegungssumme ohne
Umbuchungen und Stornos. Sobald Konten, Status, Kategorie, Zeitraum oder Text
eingeschränkt sind, zeige ausdrücklich „Gefilterte Summe ist kein
Kontostand“.

Zeige oberhalb jeder Sammelkontoblatt-Tabelle einen währungsgetrennten
Tagesverlauf. Ungefiltert beginnt jede Währungsserie mit der Summe der
Eröffnungssalden ihrer eingeschlossenen offenen Konten und speichert pro Tag
den Wert nach dessen letzter chronologischer Buchung; Stornos verändern ihn
nicht. Sobald irgendein Konto-, Status-, Kategorie-, Klassen-/Tag-, Zeitraum-
oder Textfilter aktiv ist, wechsle fachlich auf eine bei null beginnende,
kumulierte Bewegungssumme der Sichtmenge. Schließe dabei Stornos und beide
Seiten von Umbuchungen aus und nenne die Serie sichtbar „Gefilterte
Bewegungssumme“, niemals Saldo. Zeige bei insgesamt weniger als 30 Tageswerten
Punkte. Hover über einem Tag wählt die zugehörige letzte wirksame Buchung in
derselben Tabelle. Haupt- und zweite Sammelansicht verwenden denselben reinen
Snapshot-Algorithmus; teste Eröffnungssalden, Tagesverdichtung, Zukunft,
Storno, Transferausschluss, Navigation und Währungstrennung deterministisch.

Erlaube Mehrfachkategorisierung nur für UUIDs real gespeicherter Buchungen;
errechnete Zukunftszeilen dürfen niemals an den Repository-Commit gelangen.
Systemdruck und PDF exportieren exakt die sichtbaren Spalten und Zeilen samt
Filterbeschreibung und Zukunftsvorgängen.

Speichere benannte Sammelansichten deterministisch als JSON in lokalen
Benutzereinstellungen: UUID, Name, Kontenmenge, Status, Kategorieauswahl,
Zeitraum, benutzerdefinierte Grenzen, Zukunftsschalter, Zeilenmodus und
Spaltenmenge. Beim Laden entferne nicht mehr existierende Konten und
normalisiere leere Spalten auf den Standard. Teste Filterkombination,
Währungstrennung, Stornoausschluss, Zukunftssaldo und JSON-Roundtrip.

Ergänze einen persistenten Schalter `Zweite Ansicht`. Bei Aktivierung stehen
Hauptansicht und `Sammelansicht B` gleichzeitig nebeneinander. Ansicht B
besitzt eine eigene lokale Kontenmenge, eigene Status-, Kategorie- und
Zeitraumfilter sowie einen eigenen Zukunftsschalter. Sie nutzt denselben
reinen Query- und Saldoalgorithmus, zeigt Konto, Empfänger/Zweck,
vollständigen Kategoriepfad, Betrag und Saldo und kennzeichnet gefilterte
Summen ebenfalls als Nicht-Kontostand. Globale Volltextsuche und
Ein-/Zweizeilenmodus dürfen gemeinsam bleiben.

Direkte Berichtsaufrufe transportieren eine typisierte
`TransactionReportQuery` per interner Navigation an die Berichtswerkstatt.
Erweitere die Query rückwärtskompatibel nur um optionale Felder:
`transactionIDs`, `exactPayee` und `includeForecast`. Exakte UUID-Auswahl
bildet alle sichtbaren Zeilen einschließlich errechneter Zukunft ab. Für
Empfänger vergleiche getrimmt, ohne Groß-/Kleinschreibung und Diakritika;
Kategorie und Tag verwenden die vorhandenen hierarchischen Filter.

Die Berichtswerkstatt zeigt eine sichtbare Leiste für die Direktauswahl und
einen Befehl zum Lösen. `includeForecast` ergänzt ausschließlich für diesen
Query die gleichen 365-Tage-Occurrences; normale Berichte ändern ihr
Verhalten nicht. Alte JSON-Berichtsvorlagen ohne die optionalen Felder müssen
weiter decodieren. Teste exakte UUID-Selektion, diakritischen Empfänger,
Zukunftseinbeziehung und alten Nil-Roundtrip.

# Reproduzierbarer Szenario- und Liquiditätsausbau

Ergänze SQLite-Schema 35 um `forecast_scenarios` und
`forecast_scenario_entries`. Ein Szenario besitzt UUID, Namen, Notiz,
Aktivstatus, Erstell-/Änderungszeit und Version. Eine Position besitzt UUID,
Szenario- und Konto-Fremdschlüssel, kalendarisches Datum, Namen,
`Int64`-Minor-Units, Einbeziehungsstatus, Notiz, Zeiten und Version. Löschen
eines Szenarios löscht seine Positionen per Fremdschlüssel-Kaskade; alle
Speicher- und Löschvorgänge werden auditiert. Die Migration von Schema 34
muss Konten und Buchungen unverändert erhalten und mit Integrität `ok` enden.

Implementiere eine reine `LiquidityForecastEngine`, die für genau eine
Währung Tages-, ISO-Wochen- oder Kalendermonatsintervalle bildet. Der
Anfangsbestand besteht aus Eröffnungssalden und allen nicht stornierten,
nicht erwarteten Buchungen vor dem Starttag. Innerhalb des Zeitraums werden
reale Buchungen, vorgemerkte und erwartete Buchungen, nicht abgelehnte oder
stornierte Zahlungsaufträge, aktive Dauerauftragsfälligkeiten, allgemeine
Serientermine und aktivierte Szenariopositionen berücksichtigt. Gib je
Intervall Anfang, Bewegung, Schluss, Minimum, Maximum und die enthaltenen
Positionen samt Herkunft zurück.

Verhindere Doppelzählung mit stabiler Priorität: reale Buchung vor
Zahlungsauftrag vor Dauerauftrag vor allgemeinem Serientermin. Fasse nur
Positionen mit exakt gleichem Konto, lokalem Kalendertag, Minor-Unit-Betrag
und großschreibungs-/diakritikaunabhängig normalisierter Bezeichnung
zusammen. Szenariopositionen sind bewusste additive Annahmen und werden nie
dedupliziert. Abgelehnte/stornierte Aufträge, beendete/pausierte
Daueraufträge, deaktivierte Szenariopositionen und stornierte Buchungen
zählen nicht.

Baue eine Szenarioverwaltung aus Master-Detail-Liste und Editor. Rechts
stehen Intervall, 30/90/365-Tage-Horizont, Währung und Bereich `alle`,
`Konto` oder `Kontengruppe`. Zeige Basis und gewähltes aktives Szenario mit
Schlusssaldo, Minimum, Maximum, Anzahl unterdeckter Intervalle und
Szenarioeffekt. Jede Detailzeile nennt Datum, Herkunft, Bezeichnung, Konto und
Betrag. Betragseingaben müssen die Nachkommastellen der gewählten
Kontowährung verwenden; ein Währungswechsel setzt eine unpassende
Bereichsauswahl zurück.

# Reproduzierbarer OFX-/QFX-Kontoauszugsimport

Implementiere OFX/QFX ohne zusätzliche Abhängigkeit für zwei verbreitete
Dialekte: wohlgeformtes OFX-2-XML und OFX-1/QFX-SGML mit nicht geschlossenen
Blatt-Tags. Akzeptiere ausschließlich Dokumente mit `<OFX>` und
`STMTRS`/`CCSTMTRS`; begrenze Eingaben auf 50 MB und 200.000 Buchungen.
Erfasse je Konto `BANKID`, `ACCTID`, `ACCTTYPE`, Kreditkartenkennzeichen und
`CURDEF`. Erzeuge einen stabilen externen Kontoschlüssel aus diesen Feldern.

Erfasse aus jedem `STMTTRN` mindestens `TRNTYPE`, `DTPOSTED`, optional
`DTUSER`, `TRNAMT`, `FITID`, `NAME`, `MEMO`, `CHECKNUM` und `REFNUM`.
Datumswerte verwenden die ersten acht Ziffern als gregorianischen UTC-Tag;
Beträge werden dezimal und bankers-rounded in Minor Units umgerechnet.
Begrenze Freitextlängen. Fehlerhafte Datensätze bleiben mit Konto und
Datensatznummer sichtbar in der Vorschau, statt teilinterpretiert zu werden.

Zeige bei mehreren externen Bank- oder Kreditkartenkonten pro Konto einen
Pflicht-Picker für ein vorhandenes lokales Konto. Filtere Auswahlkonten nach
identischer Währung und schlage nur eine eindeutige Übereinstimmung über
IBAN/Maskierung vor; bei genau einem externen Konto darf die vorherige
Zielkontoauswahl vorgeschlagen werden. Ohne vollständige Zuordnung ist die
Vorschau gesperrt.

Normalisiere anschließend jede Buchung als `FinanceTransaction` mit Herkunft
`fileImport`, Provider `OFX` beziehungsweise `QFX`, externer ID `FITID`,
Referenz und Buchungstext. Verwende den SHA-256-Hash der gesamten Quelldatei
als Paketfingerabdruck und deterministische Buchungs-UUIDs. Leite die
normalisierten Zeilen unverändert durch das bestehende gestufte Matching und
den atomaren `commitImport`; erfinde keinen zweiten Commitpfad. Teste
Mehrkonten-XML, SGML-Blatt-Tags, Kreditkarte, Valuta, Cent-Rundung,
beschädigte Zeilen, fehlende Zuordnung, Währungsabweichung, erneuten
Paketimport und SQLite-Integrität ausschließlich mit synthetischen Daten.

# Reproduzierbarer MT940-/camt.05x-Kontoauszugsimport

Erweitere denselben Kontoauszugsimport ohne neue Abhängigkeit um MT940 sowie
camt.052, camt.053 und camt.054. Akzeptiere für MT940 `.sta` und `.mt940`,
für camt `.xml`, `.c53` und `.c54`. Behalte die zentralen Grenzen von 50 MB
und 200.000 Buchungen, den SHA-256-Paketfingerabdruck, deterministische UUIDs,
die explizite Mehrkontenzuordnung, das bestehende Matching und ausschließlich
den atomaren `commitImport` bei.

Segmentiere MT940 an `:20:` und erfasse mindestens `:25:`, `:60F:`/`:60M:`,
`:61:`, fortgesetzte `:86:`-Zeilen sowie `:62F:`/`:62M:`. Interpretiere
Buchungsdatum, optionales Valutadatum, Storno-/Soll-/Habenkennzeichen,
deutschen Dezimalbetrag, Geschäftsvorfallcode, Kunden- und Bankreferenz.
Zerlege strukturierte `:86:`-Unterfelder und übernimm Empfänger,
Verwendungszweck, Gegenkonto-IBAN und BIC. Mehrere Konten einer Datei müssen
getrennte externe Kontoschlüssel erhalten.

Parse camt namespacebewusst mit `XMLParser`. Deaktiviere externe Entitäten
und weise jedes Dokument mit `<!DOCTYPE` oder `<!ENTITY` vor dem Parser als
Ganzes ab. Unterstütze `Stmt` und `Ntfctn`, IBAN oder sonstige Kontokennung,
Kontowährung/BIC, `Ntry` und optional mehrere `TxDtls`. Übernimm pro Detail
Betrag/Soll-Haben, Buchungs-/Valutadatum, Bank-, Transaktions- und
End-to-End-Referenz, Mandatsreferenz, Empfänger, IBAN/BIC, Buchungstext und
unstrukturierten Verwendungszweck. Bei Sammelbuchungen ist der Detailbetrag
maßgeblich.

Fehlerhafte Einzelbuchungen erscheinen nummeriert in der Vorschau; eine
fehlende Kontokennung verwirft nur den betroffenen Auszug. Teste synthetisch
mehrere MT940-Auszüge, strukturierte `:86:`-Felder, camt-Sammelbuchungen,
Bankidentität, Metadatenpersistenz, DTD-/ENTITY-Abweisung, fehlerhafte Daten,
atomaren SQLite-Commit, Paket-Idempotenz und Integrität.

# Reproduzierbare Buchungsaktionen im Kontoblatt

Ergänze das Kontextmenü einer einzeln markierten Buchung um `Duplizieren …`,
`Kopieren` und `In anderes Konto verschieben …`. Duplizieren darf nicht
direkt persistieren, sondern öffnet den vorhandenen Buchungseditor mit einem
frischen, aus der Quelle erzeugten Entwurf. Verwende dabei die gleiche
Normalisierung wie bei Buchungsvorlagen: neue Transaktions- und Split-UUIDs,
aktuelles Buchungsdatum, keine Referenz-, Umbuchungs-, Import- oder externe
Bankidentität und Status `gebucht`, falls die Quelle abgeglichen oder
storniert war. Erhalte Empfänger, Zweck, Konto, Betrag, Währung, Kategorie,
Klassen/Tags, Memo, Splitzeilen und Umsatzsteuer. Einzelne Umbuchungsseiten
dürfen nicht dupliziert werden.

Kopieren schreibt genau eine TSV-Zeile in die macOS-Zwischenablage. Die
Spalten sind deutsches Datum `dd.MM.yyyy`, Empfänger, Verwendungszweck,
vollständiger Kategoriepfad, deutscher Dezimalbetrag ohne Währungssymbol und
ISO-Währung. Ersetze eingebettete Tabulatoren in Feldinhalten durch
Leerzeichen, damit das Format stabil in Tabellenkalkulationen eingefügt
werden kann.

Verschieben ändert ausschließlich `transactions.account_id` in einer
`BEGIN IMMEDIATE`-Transaktion und erhöht die Version. Lade und prüfe Quelle
und Ziel innerhalb derselben Transaktion. Das Ziel muss existieren, offen,
von der Quelle verschieden und in derselben Währung sein. Abgeglichene
Buchungen und einzelne Seiten einer Umbuchung sind geschützt. Splitzeilen,
Kategorien, Klassen/Tags, Steuerdaten, Bankmetadaten und Betrag bleiben
unverändert. Schreibe bei Erfolg ein Auditereignis `move-account` mit Quell-
und Zielkonto. Der Dialog bietet ausschließlich passende Ziele an und nennt
Quelle, Betrag sowie die Schutzwirkung verständlich.

Teste atomaren Kontowechsel, Salden beider Konten, Erhalt der Split-IDs und
Bankmetadaten, identisches Ziel, geschlossenes Ziel, Währungsabweichung,
Abgleichschutz, Umbuchungsschutz, SQLite-Integrität sowie die bytegenaue
deutsche TSV-Zeile mit eingebetteten Tabulatoren.

# Reproduzierbare automatische Datensicherung

Baue auf `sqlite3_backup` auf und gib eine Sicherung niemals frei, solange sie
noch von einer WAL- oder SHM-Seitendatei abhängt. Schreibe zunächst in einen
einmaligen versteckten Zielpfad, beende den Online-Backupvorgang, führe
`wal_checkpoint(TRUNCATE)` aus, setze die Zieldatei auf `journal_mode=DELETE`,
finalisiere alle Statements und schließe die Zielverbindung. Entferne
verbliebene leere Seitendateien. Öffne die Sicherung anschließend read-only
mit SQLite-URI `immutable=1`, prüfe Finanzdateikopf und `integrity_check = ok`
und verschiebe sie erst danach atomar auf den endgültigen `.qbackup`-Namen.
Vorhandene Ziele und die Quelldatei selbst dürfen nie überschrieben werden.

Lege Autosicherungen standardmäßig im Ordner `Sicherungen` neben der
Finanzdatei ab. Die Richtlinie umfasst Aktivstatus, Mindestabstand in Stunden,
Höchstzahl und maximales Alter in Tagen; Standardwerte sind aktiv, 24 Stunden,
14 Dateien und 90 Tage. Beim Start und Beenden wird nur gesichert, wenn der
Mindestabstand abgelaufen ist und Hauptdatei, WAL oder SHM seit der neuesten
Autosicherung geändert wurden. Eine sichtbare Aktion erzwingt unabhängig vom
Zeitpunkt eine neue geprüfte Sicherung. Mengen- und Altersrotation dürfen nur
Dateien mit dem eindeutigen Autosicherungspräfix löschen, niemals manuelle
oder Vor-Migrations-Sicherungen.

Vor jeder Migration eines vorhandenen Schemas kleiner als der aktuellen
Schemafassung entsteht unabhängig von der Autosicherungsrichtlinie eine
eigene geprüfte Vor-Migrations-Sicherung. Eine Datei mit höherer unbekannter
Schemaversion wird mit verständlicher Meldung geöffnet abgewiesen und nicht
verändert. Teste Zeitprüfung, Änderungsprüfung, deaktivierte und erzwungene
Sicherung, Mengen- und Altersrotation, eigenständige Lesbarkeit ohne
Seitendateien, Quell-/Zielschutz, Alt-Schema-Sicherung, Zukunftsschema-
Ablehnung, Restore-Regression und Datenbankintegrität.

# Reparaturmodus ausschließlich auf einer Kopie

Ergänze den bestehenden Manager für atomare Finanzdateikopien um die Art
`repair`. Das Ziel muss eine neue `.qdata`-Datei in einem regulären,
nicht-symbolischen Ordner sein, darf weder existieren noch der aktiven Datei
entsprechen und erhält `0600`. Erzeuge zunächst per `sqlite3_backup` eine
vollständige versteckte Zwischenkopie. Öffne nur diese Kopie schreibbar und
führe bei aktivierten Fremdschlüsseln nacheinander `REINDEX`, `VACUUM`,
`PRAGMA optimize` und `journal_mode=DELETE` aus. Verlange anschließend eine
leere `foreign_key_check`-Ergebnismenge und `integrity_check=ok`, schließe die
Verbindung vollständig und entferne WAL-, SHM- und Journal-Seitendateien.

Validiere die Zwischenkopie danach erneut unveränderlich, setze die privaten
Rechte, berechne Größe und SHA-256 und verschiebe sie atomar auf das endgültige
Ziel. Vergleiche Größe und Hash nach dem Verschieben. Bei jedem Fehler werden
nur selbst erzeugte Zwischenartefakte entfernt; ein vorher vorhandenes Ziel
bleibt unangetastet. Die aktive Verbindung bleibt geöffnet und die
Quelldatei wird niemals durch die Reparaturkopie ersetzt. Biete die Aktion
unter `Ablage > Reparaturkopie erstellen …` mit einer Erklärung dieser
Schutzwirkung und einem Save-Panel an.

Teste die aktive Quelldatei vor und nach der Aktion bytegenau und fachlich,
öffne die fertige Kopie erneut und vergleiche Konto- und Buchungs-IDs. Prüfe
außerdem `0600`, Fremdschlüssel, Integrität, fehlende Sidecars, Selbstziel,
falsche Endung, vorhandenes Ziel, Aufräumen versteckter Zwischenartefakte und
die fortgesetzte Nutzbarkeit der aktiven Datei. Beschreibe die Funktion als
sicheren Wartungsmodus für eine lesbare Kopie, nicht als Garantie zur Rettung
beliebig physisch zerstörter SQLite-Dateien.

# Reproduzierbare Fremdwährungsbuchungen

Speichere jede Buchung zwingend in der Währung ihres Kontos. Ergänze für einen
abweichenden Beleg die drei gemeinsam verpflichtenden Felder
`original_amount_minor`, `original_currency` und `exchange_rate_scaled`.
`exchange_rate_scaled` ist der Kontowährungsbetrag je Einheit Originalwährung
mit dem festen Faktor 100.000.000. Original- und Kontobetrag müssen ungleich
null sein, dasselbe Vorzeichen besitzen und nach Umrechnung höchstens eine
kleinste Kontowährungseinheit voneinander abweichen. Teilweise gesetzte oder
gleichlautende Währungen werden abgewiesen.

Ermittle die Nachkommastellen einer ISO-Währung über `NumberFormatter`, führe
sämtliche Rechnungen mit `Decimal` aus und runde `.bankers`. Ein deutsches
Komma ist das Dezimaltrennzeichen, Punkte davor sind Gruppierungszeichen; bei
Eingaben ohne Komma bleibt der Punkt Dezimaltrennzeichen. Speichere niemals
binäre Fließkommazahlen in Finanzfeldern.

Eine Umbuchung gleicher Währung verlangt identische kleinste Einheiten. Bei
unterschiedlichen Währungen nimmt der Dialog getrennte positive Abgangs- und
Gutschriftbeträge entgegen. Schreibe beide Seiten in einer SQLite-Transaktion:
Quelle negativ in Quellwährung, Ziel positiv in Zielwährung, jeweils mit dem
anderen Betrag als Originalwert und dem passenden reziproken Kurs. Prüfe
vorher Existenz, Verschiedenheit und Offenstatus der Konten. Keine ungültige
Eingabe darf eine einzelne Transferseite hinterlassen.

Zeige im Buchungseditor Originalbetrag, ISO-Code und den abgeleiteten Kurs.
Zeige im Transferdialog beide Kontowährungen und eine Live-Kursvorschau. Die
zweizeilige Kontoblattansicht zeigt den Originalbetrag unter dem Kontobetrag.
Buchungsvorlagen erhalten Fremdwährungsdaten; Transferidentitäten bleiben wie
bisher ausgeschlossen. Migriere Schema 29 atomar auf Schema 30 und sichere
vorher die unveränderte Schema-29-Datei. Teste JPY/KWD-Nachkommastellen,
Kursrundlauf, Vorzeichen, Kontowährungszwang, atomare Transfers, Salden,
Persistenz, Vorlagen, 29→30-Migration, Zukunftsschema und Integrität.

# Reproduzierbares allgemeines Buchungs-Undo

Migriere Schema 30 atomar auf Schema 31 und lege
`transaction_undo_runs` mit monotoner Sequenz, stabiler UUID, Titel,
vollständigem `before_json`, vollständigem `after_json`, Anzahl, Zeitstempel
und einmaligem `undone_at` an. Codiere Arrays vollständiger
`FinanceTransaction`-Snapshots mit sortierten Schlüsseln und Millisekunden-
Datumswerten. Normalisiere vor dem Vergleich Buchungs-IDs, Tags,
Splitreihenfolge und Split-Tags deterministisch. Speichere kein partielles
Feld-Diff, weil auch Split-IDs, Steuerdaten, Bankmetadaten und beide Seiten
einer Umbuchung exakt wiederherstellbar bleiben müssen.

Erzeuge das Undo-Paket in derselben SQLite-Transaktion wie die fachliche
Mutation. Erfasse manuelles Erstellen und Bearbeiten, Kontowechsel,
Kategorie-/Klassen-Massenorganisation, bestätigtes Löschen und atomare
Umbuchungserstellung. Bei Löschung einer einzelnen Transferseite umfasst der
Vorher-Snapshot zwingend beide Seiten. Leere oder wirkungslose Änderungen
erzeugen keinen Undo-Eintrag. Die jüngste aktive Änderung wird ausschließlich
über die monotone Sequenz bestimmt, nicht über einen Zeitstempel mit möglicher
Kollision.

Vor dem Undo lade alle betroffenen Buchungen erneut und vergleiche ihren
normalisierten vollständigen Zustand mit `after_json`. Fehlt, erscheint oder
unterscheidet sich eine Seite, brich die gesamte Operation ohne Schreibzugriff
ab. Schütze abgeglichene Buchungen zusätzlich. Lösche erst innerhalb einer
Transaktion alle erwarteten Nachher-Seiten, schreibe dann sämtliche Vorher-
Snapshots mit ihren ursprünglichen IDs zurück, markiere das Paket einmalig als
verwendet und schreibe ein Auditereignis. Ein zweiter Aufruf desselben Pakets
muss fehlschlagen.

Zeige das jüngste Paket im Kontoblatt als semantisch beschrifteten
`Rückgängig`-Button mit Titel und Buchungsanzahl. Verlange eine Bestätigung,
erkläre den Konfliktschutz und lade nach Erfolg Buchungen, Salden und den
nächsten Undo-Eintrag neu. Teste vollständige Split-/Tag-Wiederherstellung,
Erstellung, Bearbeitung, Löschung eines Umbuchungspaars, Verschieben,
Massenorganisation, stale Snapshots, Einmaligkeit, 30→31-Migration und
SQLite-Integrität.

# Hashadressierte Beleganhänge für Buchungen

Migriere Schema 31 atomar auf Schema 32. Lege `attachment_blobs` mit
SHA-256-Primärschlüssel, MIME-Typ, positiver Bytezahl, Original-BLOB und
Erstellungszeit sowie `attachment_links` mit UUID, Zieltyp, Ziel-ID,
Blob-Fremdschlüssel, Originaldateiname, Quelle, getrenntem OCR-Text und
Hinzufügezeit an. Erlaube als Zieltypen Konto, Buchung, Vertrag, Wertpapier und
Inventar. Dedupliziere Inhalte global nach SHA-256, Verknüpfungen aber nach
Ziel, Hash und Dateiname. Speichere Inhalt und Link in derselben
SQLite-Transaktion und verifiziere bei einer Hashkollision zusätzlich MIME,
Größe und vollständige Bytes. Da die BLOBs in derselben SQLite-Datei liegen,
müssen Online- und Vor-Migrations-Sicherungen Belege ohne separaten
Dateibaum vollständig enthalten.

Validiere vor dem Lesen eine reguläre, nicht symbolische Datei zwischen einem
Byte und 50 MiB sowie einen höchstens 255 UTF-8-Bytes langen Dateinamen ohne
Steuerzeichen. Akzeptiere ausschließlich PDF, PNG, JPEG, TXT, CSV, QIF und XML.
Prüfe bei Binärtypen die Magic Bytes und bei Texttypen NUL-Freiheit und
gültiges UTF-8; die Endung allein genügt nicht. Rufe danach einen injizierbaren
Virenscan-Hook auf. Jeder Fehler muss vor einem Datenbank-Commit enden.

Der Editor einer bereits gespeicherten Buchung listet beliebig viele Anhänge
mit Name, MIME und Größe. Er nimmt genau eine Datei über einen typgefilterten
Dateidialog oder Drag-and-drop entgegen. Entfernen ist destruktiv zu
bestätigen; der Blob wird nur gelöscht, wenn keine weitere Verknüpfung darauf
zeigt. Öffnen verlangt eine gesonderte Bestätigung, lädt den BLOB, prüft Größe
und SHA-256 erneut und schreibt erst dann eine Vorschau mit Verzeichnisrechten
0700 und Dateirechten 0600 in den Benutzer-Cache. Übergib nur erlaubte Typen an
die registrierte macOS-App; starte keine ausführbaren Typen.

Integriere die Semantik in das allgemeine Buchungs-Undo: Wird die Erstellung
einer Buchung rückgängig gemacht, entferne deren inzwischen ergänzte Links und
danach verwaiste BLOBs atomar. Bei einer gelöschten Buchung bleiben Links zur
Wiederherstellung erhalten und erscheinen nach dem Undo wieder. Teste
Deduplizierung auf einem und mehreren Zielen, Metadaten und SHA-256,
Backup-Roundtrip, Vorschauinhalt und 0600, Entfernung der letzten Referenz,
unzulässige Endung, falsche Magic Bytes, Symlink, 50-MiB-Grenze, fehlendes
Ziel, Scan-Abbruch ohne Teilwirkung, manipulierten gespeicherten Inhalt,
31→32-Migration, Zukunftsschema, beide Undo-Randfälle und SQLite-Integrität.

Extrahiere die Anhangszeilen anschließend in eine gemeinsame SwiftUI-
Komponente. Verwende sie unverändert im Editor einer bestehenden Buchung und
eines bestehenden Kontos sowie in den Detailakten eines ausgewählten Vertrags,
Wertpapiers und Inventargegenstands. Die Komponente lädt beim Erscheinen und
bei einem Zielwechsel neu, verwirft dabei ausstehende Öffnen-/Löschziele und
besitzt einen stabilen Accessibility-Bezeichner aus Zieltyp und UUID.
Beschrifte Öffnen und Entfernen jeweils mit dem vollständigen Dateinamen für
VoiceOver. Prüfe mit einem Integrationstest, dass derselbe Originalinhalt an
allen vier zusätzlichen Zieltypen genau einen BLOB und vier getrennte Links
erzeugt, je Fachakte korrekt geladen wird und nach Entfernung der letzten
Referenz vollständig verschwindet.

# Verifizierter offener Anhangsexport und sichere Notizlinks

Erweitere die gemeinsame Anhangskomponente um `Exportieren …`. Verwende den
macOS-Speicherdialog mit Originaldateiname und passendem Inhaltstyp. Behandle
eine durch den Systemdialog bestätigte vorhandene Datei als ausdrückliche
Ersetzungsfreigabe; überschreibe sonst niemals still.

Lade den Exportinhalt ausschließlich über denselben internen Prüfpfad wie die
Vorschau: Verknüpfung und BLOB müssen vorhanden sein, gespeicherte Bytezahl und
SHA-256 müssen den Originalbytes entsprechen. Akzeptiere nur lokale Ziele mit
derselben Dateiendung wie das Original (JPG/JPEG gelten als äquivalent) und
niemals die Finanzdatei selbst. Der Zielordner muss ein echtes Verzeichnis
sein. Ein vorhandenes Ziel muss eine reguläre, nicht symbolische Datei sein;
Pakete und Verzeichnisse sind nicht ersetzbar.

Schreibe in eine zufällig benannte neue Staging-Datei im Zielordner, setze
0600 und verschiebe beziehungsweise ersetze sie erst abschließend. Prüfe am
fertigen Ziel erneut Bytezahl und SHA-256; lösche ein inkonsistentes Ergebnis
und protokolliere nur einen erfolgreichen Export mit Hash und Dateiname im
Audit. Teste Neu-Export, 0600, stilles Überschreiben, ausdrücklich bestätigtes
Ersetzen, falsche Endung, Symlinkziel, unverändertes Symlinkziel, manipulierten
BLOB ohne Ausgabedatei und SQLite-Integrität.

Implementiere für Freitextnotizen eine eigenständige
`SecureNoteLinkPolicy`. Erkenne Links mit `NSDataDetector`, biete jedoch nur
HTTPS-URLs mit Host und ohne eingebettete Zugangsdaten sowie lokale `file:`-
URLs ohne entfernten Host als Aktionen an. Normale HTTP-/FTP-/Script-Schemata
dürfen nicht als öffnbarer Button erscheinen.

Zeige Links über eine gemeinsame `SecureNoteView` in Buchungsnotiz,
Kontobeschreibung, Vertrag, Wertpapier und Inventar. Ein Klick darf nur einen
Bestätigungsdialog öffnen. Erst die bestätigte Aktion validiert das Ziel
erneut. Lokale Ziele müssen dann als reguläre, nicht symbolische,
nicht ausführbare Datei existieren; blockiere Verzeichnisse, Pakete,
ausführbare Rechte und bekannte Programm-, Skript-, Shortcut- und
Terminalendungen. Übergib das Ziel erst danach an `NSWorkspace`. Teste
Erkennung und Anzeige ohne URL-Abfrageparameter, HTTPS, lokale Datei, HTTP,
FTP, URL-Zugangsdaten, ausführbares Skript und Symlink.

# Deterministischer Kontenblatt-Referenzdatensatz und Leistungs-Gate

Erzeuge für Tests und die Startoption `-reference-demo` in einer leeren,
temporären Finanzdatei einen vollständig synthetischen Datensatz. Verwende
stabile UUIDs und genau 12 Konten in den vier Standardgruppen Bankkonten,
Bargeld, Vermögen und Verbindlichkeiten. Verteile die Konten auf EUR, USD und
CHF. Erzeuge genau 10.000 Buchungen über 3.653 Kalendertage, davon genau 200
Splitzeilen und 150 ausgeglichene, jeweils aus zwei Buchungsseiten bestehende
Umbuchungen. Liefere ein Manifest mit den Anzahlen, frühestem/spätestem Datum
und der erwarteten Nettosumme je Währung. Prüfe die Berichtssummen gegen einen
echten `TransactionReportEngine`-Snapshot und anschließend die
SQLite-Integrität. Private QIF-Dateien sind dafür niemals Fixture oder Quelle.

Validiere den vollständigen Stapel vor dem Schreiben und speichere ihn mit
wiederverwendeten SQLite-Statements in genau einer Transaktion. Lade
Buchungen, Splits sowie Buchungs- und Split-Tags in gebündelten Abfragen ohne
N+1-Muster. Dekodiere den festen Datenbanktag `yyyy-MM-dd` durch einen
validierenden gregorianischen Festformat-Parser, nicht durch einen
`DateFormatter` pro Zeile.

Baue den globalen Volltextindex bei mehr als 25.000 Buchungen verzögert im
Hintergrund auf, damit der vollständig geladene Kern sofort bedienbar ist.
Bis zur Fertigstellung muss die direkte Suchprüfung korrekt bleiben. Verwirf
das Ergebnis, wenn zwischenzeitlich eine neuere Store-Generation geladen
wurde.

Halte den 100.000-Buchungen-Test opt-in. Erweitere den 10.000er Datensatz in
derselben Datei um 90.000 validierte Buchungen und fordere auf dem Testsystem:
Persistierung unter 30 Sekunden, erneutes Öffnen samt vollständig geladenem
`FinanceAppStore` unter 3 Sekunden, Kontenblattberechnung unter 500
Millisekunden und einen Standardbericht unter 2 Sekunden. Protokolliere die
Messwerte als XCTest-Aktivität. Die bereits vorhandene Nutzerabfrage gegen
100.000 fertig indexierte Dokumente muss weiterhin unter 100 Millisekunden
bleiben.

# Vollständige Kontostammdaten und datiertes Schließen

Migriere Schema 38 atomar auf 39. Ergänze Konten additiv um einen frei
bezeichenbaren Untertyp, deutsche Bankleitzahl, eigenen Stichtag des
Eröffnungssaldos, Schließdatum und eine optionale Selbst-Fremdschlüssel-
Zuordnung zu einem Verrechnungs-, Anlage-, Darlehens- oder Gegenkonto. Der
Fremdschlüssel verwendet `ON DELETE SET NULL` und einen Index. Bestandskonten
behalten alle Werte; neue Felder migrieren leer beziehungsweise `NULL`.
Setze auf jeder SQLite-Verbindung einen Busy-Timeout von fünf Sekunden, damit
eine kurz auslaufende Vorgängerinstanz die Migration nicht unnötig abbricht,
ohne dauerhafte Konkurrenz zu verschweigen.

Trimme den Untertyp, begrenze ihn auf 80 UTF-8-Bytes und verbiete
Steuerzeichen. Normalisiere Leerzeichen aus der BLZ und akzeptiere nur leer
oder genau acht Ziffern. Ein Schließdatum darf nur bei geschlossenem Konto
stehen. Der Saldo-Stichtag darf nicht vor der Kontoeröffnung liegen, das
Schließdatum nicht vor dem ersten Eröffnungs-/Saldo-Stichtag. Das zugeordnete
Konto muss in derselben Finanzdatei existieren und darf nicht das Konto selbst
sein.

Zeige alle Felder im Kontoeditor und den Untertyp zusätzlich in der
Kontenübersicht. Der bestätigte direkte Schließen-Ablauf setzt den heutigen
Kalendertag; Wiederöffnen entfernt das Datum. Nimm Untertyp, BLZ,
Saldo-Stichtag und Schließdatum in die globale Kontenblattsuche auf. Teste
38→39-Migration mit unverändertem Bestandskonto, vollständigen Rundlauf,
Suchtext, ungültige BLZ, Selbst-/Fremdreferenz, Datumsfolgen,
Zukunftsschema-Schutz und SQLite-Integrität.

# Mehrere unabhängige Finanzdateien

Ergänze native Ablagebefehle für `Neue Finanzdatei …` mit `⇧⌘N`,
`Finanzdatei öffnen …` mit `⌘O` und ein dynamisches Menü der höchstens zehn
zuletzt verwendeten Dateien. Finanzdateien tragen zwingend die Endung
`.qdata`. Öffne nur vorhandene reguläre, nicht symbolische Dateien. Beim
Neuanlegen muss das Ziel fehlen und sein Elternordner ein reales, nicht
symbolisches Verzeichnis sein; erzeuge niemals einen stillen Ersatz.

Validiere den vom Dateinamen abgeleiteten Anzeigenamen vor dem Anlegen:
getrimmt, nicht leer, höchstens 120 UTF-8-Bytes und ohne Steuerzeichen. Vor
jedem Wechsel ist eine erzwungene SQLite-Online-Sicherung der bisherigen
Datei Pflicht. Konstruiere und migriere die neue Repository-Instanz zunächst
als Kandidat. Erst danach ersetze die aktive Referenz, lade sämtliche
publizierten Sammlungen neu, verwerfe Kontoauswahl und Suche, schließe offene
Editoren und schließe die alte Verbindung. Falls Öffnen oder Laden scheitert,
bleiben alte Repository-Instanz, Daten und Auswahl der aktiven Datei erhalten.

Speichere den kanonischen Pfad der zuletzt erfolgreichen Datei und eine
deduplizierte MRU-Liste mit höchstens zehn noch vorhandenen Dateien in
`UserDefaults`. Öffne beim normalen Start die zuletzt verwendete Datei nur,
wenn sie weiterhin eine reguläre direkte Datei ist; verwende andernfalls die
Standarddatei. Demo- und Teststarts verändern diese Präferenz nicht. Zeige im
Statusbereich den Namen und als Hilfetext den vollständigen Pfad.

Teste mit zwei realen temporären SQLite-Dateien, dass Konten strikt getrennt
bleiben, Wechsel in beide Richtungen, Dateikopf, MRU-Reihenfolge und erzwungene
Sicherung funktionieren. Teste außerdem beschädigte Datei, Symlink, falsche
Endung, vorhandenes Neuziel und ungültigen Namen; bei allen Fehlern muss der
ursprüngliche Datenbestand aktiv und unverändert bleiben.

# Schließen, geprüfte Dateikopie und Archivsnapshot

Ergänze im Ablage-Menü bestätigtes `Finanzdatei schließen`, `Kopie der
Finanzdatei erstellen …` und `Finanzdatei archivieren …`. Schließen muss
zuerst unabhängig von der normalen Sicherungseinstellung eine geprüfte
SQLite-Online-Sicherung erzeugen. Nur bei Erfolg schließt es die Verbindung,
bricht den Hintergrundindex ab und leert ausnahmslos alle publizierten
Finanzdaten, Auswahl, Suche und Index. Danach müssen Öffnen und Neuanlegen
ohne App-Neustart funktionieren.

Eine Kopie ist eine vollständige eigenständige `.qdata`-Datei mit Modus 0600.
Ein Archiv ist derselbe konsistente SQLite-Snapshot mit Endung `.qarchive`
und Modus 0400; es wird nicht über den normalen Öffnen-Befehl bearbeitbar
gemacht. Beide Operationen akzeptieren nur ein noch nicht vorhandenes Ziel in
einem regulären, nicht symbolischen Zielordner und niemals die aktive Datei.

Erzeuge zunächst eine zufällig benannte versteckte Staging-Datei im
Zielordner. Verwende SQLite Online Backup, schließe WAL/SHM ab und fordere
`PRAGMA integrity_check=ok`. Berechne Größe und SHA-256 streamend, setze die
Dateirechte und verschiebe erst dann atomar an das endgültige Ziel. Berechne
Größe und SHA-256 dort erneut; bei Abweichung entferne das inkonsistente
Ergebnis. Vorhandene Ziele werden auch nach einer Dateidialog-Bestätigung nie
ersetzt.

Teste Inhalt und Integrität der Kopie, 0600, Archivvalidierung, 0400,
identischen SHA-256, vorhandenes Ziel, Selbstziel, falsche Endung,
Symlink-Zielordner und das Fehlen von Staging-Resten. Teste beim Schließen die
Sicherung, vollständige Zustandsleerung, Wiederöffnen und Neuanlegen in der
zuvor dateilosen Sitzung. Verändere nach dem Archivieren den Arbeitsbestand,
stelle das Archiv über den validierenden Sicherungsdialog wieder her und prüfe
Inhalt, aktive Zieldatei sowie Integrität des rückgesicherten Bestands.

# Schreibgeschützte Wiederherstellungsvorschau

Ersetze die pauschale Restore-Warnung durch eine modale, vollständig per
Tastatur bedienbare Inhaltsvorschau. Kopiere die vom Dateidialog gewählte
Sicherung zunächst in eine zufällige Tempdatei und öffne ausschließlich diese
Kopie read-only über SQLite-URI `immutable=1`. Fordere reguläre Datei ohne
Symlink, Finanzdateikopf und `integrity_check=ok`. Lies Finanzdateiname,
Basiswährung, `user_version`, Anzahl der Konten, Kategorien und Buchungen,
jüngstes Buchungsdatum, Dateigröße und Änderungsstand. Zeige alle Werte vor
der destruktiven Bestätigung sichtbar an.

Schema 0 und unbekannte neuere Schemata müssen vor Sicherheitskopie,
Schließen oder Austausch der aktiven Datei abgewiesen werden. Die Meldung
nennt gefundene und maximal unterstützte Version. Abbrechen, Dateifehler und
erfolgter Restore entfernen die Tempkopie. Teste den Vorschauinhalt gegen eine
echte Sicherung, identischen SHA-256 vor und nach der Vorschau, das Fehlen von
WAL/SHM sowie die Ablehnung eines integeren Zukunftsschemas bei vollständig
unveränderter aktiver Finanzdatei.

# Versionierter CSV-/TSV-Profilassistent

Setze vor die bestehende Importvorschau einen modalen Profilassistenten. Ein
`CSVImportProfile` muss schema-versioniert und `Codable` sein und Encoding
(UTF-8, Windows-1252, ISO-Latin-1), Trennzeichen (Semikolon, Komma, Tab),
Kopfzeile, Datumsformat (`dd.MM.yyyy`, `dd.MM.yy`, ISO, US), Dezimal- und
Tausenderzeichen, Betrag oder getrenntes Soll/Haben sowie eine freie
Quellspaltenzuordnung speichern. Unterstütze Buchungs-/Valutadatum, Empfänger,
Zweck, Betrag/Soll/Haben, Kategorie, Notiz, Referenz, externe Transaktions-ID,
Provider, Gegenkonto-IBAN/-BIC, End-to-End-ID, Mandatsreferenz, Gläubiger-ID,
Buchungstext und Banksaldo nach der Buchung.

Erkenne ein Ausgangsprofil deterministisch, zeige aber stets die ersten 20
Rohdatenzeilen und lasse jede Annahme ändern. Der Parser muss CRLF,
Anführungszeichen, verdoppelte Anführungszeichen, maskierte Trennzeichen und
Zeilenumbrüche innerhalb maskierter Felder korrekt behandeln und nicht
geschlossene Felder ablehnen. Lies Geld strikt dezimal und währungsabhängig
ohne `Double`; Soll ist negativ und Haben positiv. Weise gleichzeitig belegte
Soll-/Haben-Felder und ungültige Datums-/Betragswerte mit echter
Quellzeilennummer zurück.

Löse Kategorien über den vollständigen Pfad auf. Ein einfacher Blattname ist
nur bei Eindeutigkeit zulässig; unbekannte oder mehrdeutige Kategorien dürfen
nicht still entfallen. Speichere benannte Profile ohne Buchungsdaten lokal als
versioniertes JSON, erhöhe bei jeder Änderung desselben Profils die Revision
und lehne unbekannte neuere Schemata ab. Nach dem Assistenten müssen alle
gültigen Zeilen unverändert das vorhandene gestufte Import-Matching mit
Datumsfenster, Einzelfallentscheidung und atomarem Commit durchlaufen.

Teste mindestens automatische Erkennung mit Umlaut-Headern, Windows-1252,
US-Zahlen/Datum, Soll/Haben, mehrzeilige Felder, vollständige Kategoriepfade,
Dateien ohne Kopfzeile, unbekannte Kategorien, zeilengenaue Fehler,
Profilrevision, JSON-Rundlauf und Zukunftsschema-Ablehnung.

# Unabhängige Berichtsfenster

Ergänze die buchungsbasierte Berichtswerkstatt um `Neues Fenster`. Verpacke
die vollständige aktuelle `TransactionReportQuery`, den sichtbaren Titel, den
kanonischen Pfad der aktiven Finanzdatei und eine bei jedem Öffnen neue UUID in
einen codierbaren, hashbaren `ReportWindowRequest`. Verwende ein typisiertes
SwiftUI-`WindowGroup`, damit zwei identische Abfragen trotzdem als zwei
unabhängige macOS-Fenster geöffnet werden können.

Das externe Fenster muss dieselben Filter, Gruppierungen, Diagramme,
Drill-downs, Vorlagen, CSV-/HTML-/XLSX-/PDF-Ausgaben, Zwischenablage und Druck
wie der interne Bericht bereitstellen. Es verwendet denselben publizierten
Datenstand, hält aber seine eigene editierbare UI-State-Kopie. Titel und
komplette Query müssen den Codable-Rundlauf verlustfrei überstehen.

Binde jedes Fenster an die Finanzdatei, aus der es geöffnet wurde. Wenn die
aktive Datei geschlossen oder gewechselt wird, darf die gespeicherte Query
nicht auf den neuen Bestand angewandt werden; zeige stattdessen den erwarteten
Dateipfad und einen klaren Sperrhinweis. Eine beschädigte oder inkompatible
Query erhält einen eigenen Fehlerzustand. Teste Query-Rundlauf, Pfadbindung,
Nil-/Fremddatei, eindeutige Fenster-UUIDs und den vollständigen App-Build.

# Berichtsfenster wieder integrieren und Geometrie sichern

Jedes externe buchungsbasierte Berichtsfenster erhält in der Toolbar die
Aktion `Ins Hauptfenster`. Übergib die aktuell im Fenster bearbeitete Query
und den sichtbaren Titel als typisierten `TransactionReportLaunchRequest` per
App-interner Notification. Normalisiere einen leeren Titel zu `nil` und gib
jedem Launch eine frische UUID, damit auch eine inhaltlich identische Abfrage
die Hauptansicht sicher neu initialisiert.

Die Hauptansicht akzeptiert sowohl den neuen typisierten Launch als auch die
bisherigen direkten `TransactionReportQuery`-Aufrufe aus dem Kontenblatt. Sie
wechselt zu `Auswertungen`, rekonstruiert `ReportsView` anhand der Launch-ID
und bewahrt einen mitgegebenen Titel. Nach erfolgreicher Übergabe wird das
Außenfenster geschlossen und das registrierte Hauptfenster aktiv in den
Vordergrund geholt. Bei gesperrter Fremddatei oder beschädigter Query bleibt
die Aktion deaktiviert.

Registriere das Hauptfenster über einen transparenten `NSViewRepresentable`-
Host. Gib jedem externen Fenster einen stabilen, aus seiner UUID abgeleiteten
AppKit-Frame-Autosave-Namen, damit macOS Position und Größe dieser konkreten
Fensteridentität speichert und wiederherstellt. Teste Titelnormalisierung,
verlustfreie Query-Übergabe und die deterministische Autosave-ID.

# Eigenständige Fenster für alle Fachauswertungen

Erweitere die Fensterarchitektur auf `Kontosalden und Nettovermögen`,
`Umsatzsteuer`, `Kredite, Zins und Tilgung`, `Zeitraumvergleich`,
`Budgetvergleich`, `Verträge und Inventar` sowie `Freistellungsaufträge`.
Jeder Dialog erhält `Neues Fenster` und übergibt seinen vollständigen
aktuellen Queryzustand, nicht bloß den berechneten Snapshot.

Modelliere eine codierbare, hashbare `SpecializedReportWindowRequest` mit
frischer UUID, Fachberichtstyp, kanonischem Finanzdateipfad und typisiert
codiertem Payload. Verwende für den Budgetbericht einen Payload aus Budget-ID
und Query. Rekonstruiere im typisierten SwiftUI-`WindowGroup` exakt die
passende Berichtsansicht und initialisiere alle editierbaren Filter aus dem
Payload. Gleiche Abfragen müssen getrennte Fensteridentitäten erhalten.

Sperre die Darstellung bei geschlossener oder abweichender Finanzdatei und
zeige bei beschädigtem oder typfremdem Payload einen eigenen Fehlerzustand.
Vergib einen stabilen Frame-Autosave-Namen aus Berichtstyp und UUID. Teste
alle sieben initialen Payloadtypen auf Codable-Rundlauf, Pfadbindung,
Fensteridentität und deterministische Autosave-ID; führe danach den gesamten
Testbestand aus.

# Fachauswertungsfenster verlustfrei reintegrieren

Gib jedem ausgelagerten Fachbericht die Aktion `Ins Hauptfenster`. Der
Rückweg muss den aktuell bearbeiteten Zustand aus dem Außenfenster verwenden,
nicht den ursprünglichen Öffnungspayload. Modelliere dafür eine codierbare
Summe `SpecializedReportLaunchPayload` mit genau einem typisierten Fall je
Fachbericht und einen `SpecializedReportLaunchRequest` mit frischer UUID.

Sende den Launch über eine eigene interne Notification. Die Hauptansicht
wechselt zu `Auswertungen`, erzeugt `ReportsView` mit der Launch-UUID neu und
öffnet ausschließlich den zum Payload passenden Fachdialog. Initialisiere
darin jeden Filter und beim Budget zusätzlich die Budget-ID. Schließe danach
das Außenfenster und aktiviere das Hauptfenster.

Verbrauche den Launch nur einmal: Nach der initialen Präsentation darf ein
später manuell geöffneter Fachbericht nicht erneut die alte Außenfenster-Query
erhalten. Ein Finanzdateiwechsel setzt ausstehende Launches zurück. Sperre die
Aktion bei Fremddatei und stelle sicher, dass der Payload-Typ stets dem
Fenstertyp entspricht. Teste alle sieben initialen Payloadfälle auf Typzuordnung,
verlustfreien Codable-Rundlauf und jeweils frische Launch-Identitäten.

# Depotbestand und Erträge als achte Fachauswertung

Erweitere die typisierte Fachberichtsarchitektur um `Depotbestand und Erträge`.
Die Query speichert einen optionalen Transaktionszeitraum, Depot-,
Wertpapier-, Wertpapierart- und Währungsfilter sowie die Optionen für inaktive
Wertpapiere und geschlossene Depots. Der Zeitraum filtert ausschließlich
Transaktionen; kennzeichne den Bestand ausdrücklich als aktuelle
Momentaufnahme und erfinde keine historische Bewertung.

Erzeuge aus aktuellen `PortfolioPosition`-Werten Positionen mit Depot,
Wertpapier, Kennung, Mikrobestand, letztem Kurs, Kostenbasis, Marktwert,
unrealisiertem Gewinn und prozentualem Gewinn. Verbinde gespeicherte
`SecurityTrade`-Datensätze zu einer absteigend datierten Historie und summiere
Verkaufsgewinne, Dividenden abzüglich Gebühren und Steuern sowie Gebühren und
Steuern strikt je Währung. Ein fehlender Kurs bleibt `nil`, wird gezählt und
macht die Marktwertsumme sichtbar unvollständig; er darf niemals als
Nullkurs oder vollständige Bewertung erscheinen. Die ausgewählte Position
steuert einen Wertpapier-Drill-down.

Erzeuge deterministisches Semikolon-CSV und ein mehrseitiges PDF samt
Metadaten, Positions-, Währungssummen- und Transaktionstabelle; der
Systemdruck verwendet exakt das PDF. Binde den vollständigen Queryzustand als
achten Fall in `SpecializedReportWindowRequest` und
`SpecializedReportLaunchPayload` ein, damit Außenfenster, Dateipfadsperre,
Geometriespeicherung und verlustfreie Reintegration unverändert gelten.

Teste Filter einschließlich Groß-/Kleinschreibung der Währung, geschlossene
Depots und inaktive Wertpapiere, fehlende Kurse, Kostenbasis, Marktwert,
realisierten/unrealisierten Gewinn, Nettoertrag, Gebühren, Steuern,
Drill-down-Sortierung, deterministisches CSV, lesbares PDF und Codable-Rundlauf
aller acht Fachberichtstypen. Dokumentiere Benchmarkvergleich und
Zielallokationsbericht weiter ausdrücklich als offen.

# Ist-Asset-Allocation im Depotbericht

Erweitere den Depotbericht um eine zwischen Transaktionshistorie und
`Asset Allocation` umschaltbare Detailansicht. Lade alle
`security_allocations` beim Finanzdatei-Reload in einem einzigen sortierten
SQLite-Lesezugriff und halte sie gemeinsam mit Wertpapieren, Klassen und
Positionen im publizierten Storezustand; die View darf nicht bei jeder
Neuberechnung je Wertpapier erneut die Datenbank abfragen.

Für jede gefilterte aktuelle Position gilt die gespeicherte
Vermögensklassenmischung nur, wenn alle referenzierten Klassen existieren und
die Summe exakt 10.000 Basispunkte beträgt. Andernfalls ordne die vollständige
Position sichtbar `Nicht zugeordnet` zu. Teile Kostenbasis und bekannten
Marktwert mit Dezimalarithmetik je Mischung auf und weise den letzten
Rundungsrest deterministisch der letzten stabil sortierten Klasse zu, sodass
die Klassensummen stets exakt der Positionssumme entsprechen.

Aggregiere je Vermögensklasse und Währung: unterschiedliche Positionen,
Positionen ohne Kurs, Kostenbasis, bekannten Marktwert und Anteil am bekannten
Gesamtmarktwert derselben Währung. Ein fehlender oder nullwertiger Nenner
ergibt keinen Prozentwert. Zeige Balkendiagramm, Tabelle und einen permanenten
Formelhinweis; vermische niemals Währungen und lasse Fehlkurse nicht als
Nullbewertung in den Prozentnenner einfließen.

Erweitere Semikolon-CSV und das mehrseitige Druck-PDF um Bestände,
Währungssummen, Ist-Allokation und vollständige Transaktionshistorie. Teste
Mischklassen, Summenerhalt, Prozentwerte, nicht zugeordnete Fehlkurspositionen,
CSV- und PDF-Inhalte sowie den gemeinsamen SQLite-Ladevorgang. Kennzeichne
Zielallokation und Benchmark weiterhin als offen.

# Lotneutrale Wertpapiererträge und Gebühren

Erweitere den bestehenden Wertpapier-Vorgangseditor um `Dividende/Zins` und
`Gebühr`, ohne ein neues Schema oder eine zweite Cashflow-Wahrheit einzuführen.
Ein Ertrag speichert positiven Bruttobetrag, nichtnegative Gebühren und
Steuern sowie den daraus resultierenden Nettoertrag in `security_trades`; die
Abzüge dürfen den Bruttobetrag nicht überschreiten. Eine eigenständige Gebühr
speichert ihren positiven Betrag im Gebührenfeld. Beide Vorgänge besitzen
Stückzahl und Kurs null, erzeugen oder verbrauchen keine Lots und verändern
keinen Depotbestand. Depot und Wertpapier müssen existieren, offen
beziehungsweise aktiv sein. Verwende durchgehend die Währung des Wertpapiers,
weil ein Depot Wertpapiere verschiedener Währungen enthalten kann.

Zeige im Editor abhängig vom Vorgang nur die fachlich benötigten Felder und
nenne Kauf/Verkauf/Ertrag/Gebühr gemeinsam `Vorgang`. Die kompakte Historie
zeigt für Erträge den Nettobetrag und für Gebühren einen negativen Betrag. Die
Währungssummen des Depotberichts weisen realisierten Gewinn, Nettoertrag,
Gebühren und Steuern gleichzeitig aus; CSV und PDF übernehmen die Vorgänge
über die bestehende Transaktionshistorie.

Eine gekoppelte Buchung auf einem Verrechnungskonto, Wiederanlage,
Steuererstattung und Kapitalmaßnahmen bleiben ausdrücklich offen. Behaupte
insbesondere nicht, dass ein erfasster Wertpapiercashflow bereits einen
Bankkontosaldo verändert. Teste Validierung, Persistenz, unveränderte
FIFO-Lots, Nettoertrag und währungsgetrennte Berichtssummen.

# Historische Depotperformance mit getrennten Renditebegriffen

Lade `security_prices` beim Finanzdatei-Reload vollständig und sortiert in den
publizierten App-Zustand. Erzeuge im Depotbericht je gefilterter Währung eine
Performance-Zeitreihe vom optionalen Beginn bis zum optionalen Ende oder
Bewertungstag. Rekonstruiere Bestände aus Käufen und Verkäufen; bewerte einen
Bestand ausschließlich mit dem letzten gespeicherten Kurs am oder vor dem
Stichtag. Kauf-/Verkaufskurse dienen als nachrangiger historischer Kursbeleg,
ein expliziter Kurs desselben Tages hat Vorrang. Interpoliere keine Werte und
vermische niemals Währungen.

Behandle Kauf als externe Einzahlung einschließlich Gebühren und Steuern,
Verkauf und Nettoertrag als Auszahlung sowie eigenständige Gebühren als
Einzahlung zur Kostendeckung. Berechne getrennt absoluten Gewinn, einfache
Rendite auf Anfangswert plus positive Einzahlungen, geometrisch verknüpfte
cashflowbereinigte TWR, exaktdatierte annualisierte XIRR und annualisierte TWR.
Verwende für Geldbeträge und TWR deterministische Ganzzahl-/Dezimalarithmetik;
Gleitkomma ist nur für Wurzel-/IRR-Lösung zulässig. Ist an irgendeinem
Bewertungspunkt ein benötigter Kurs unbekannt, bleibt die betroffene Kennzahl
`Nicht berechenbar` und die Zahl fehlender Positionen wird sichtbar.

Ergänze im Depotdetail den Reiter `Performance`. Zeige Zeitraum, Anfangs- und
Endwert, alle fünf Ergebnisgrößen, Nettoeinzahlungen, Erträge, Gebühren,
Steuern sowie Formelhinweise. Weise auf fehlende Kurse und das älteste am
Endstichtag verwendete Kursdatum hin. CSV, PDF und Druck müssen dieselben
Kennzahlen und Formeln aus demselben Snapshot übernehmen. Teste persistente
Kursreihen, einen deterministischen Einjahresfall mit Kauf, Ausschüttung und
Endkurs, die Trennung von absoluter Rendite, TWR und XIRR sowie Exportinhalte.
Benchmarkvergleich und Zielallokation bleiben ausdrücklich offen.

# Umbuchungspaare im Kontoblatt atomar bearbeiten

Eine Buchungszeile mit `transferID` darf niemals den normalen
Einzelbuchungseditor oder `saveTransaction` verwenden. Leite `Bearbeiten`,
Doppelklick und die zweite Kontoblattansicht stattdessen in einen eigenen
Paar-Editor. Ermittle die Sollseite ausschließlich über den negativen und die
Habenseite über den positiven Betrag; fehlen genau zwei eindeutige Seiten,
brich ohne Schreibzugriff ab.

Der Paar-Editor hält Quell- und Zielkonto unveränderlich fest und erlaubt
Datum, Verwendungszweck sowie Abgangs- und Gutschriftsbetrag zu ändern. Bei
gleicher Währung müssen beide positiven Eingabebeträge identisch sein. Bei
verschiedenen Kontowährungen speichere beide Beträge getrennt, aktualisiere die
gegenseitigen Originalbeträge und leite beide reziproken achtstelligen Kurse
neu mit Decimal-/Banker's-Rundung ab.

Schreibe beide vorhandenen Transaktions-IDs in einer SQLite-Transaktion,
erhalte `transferID` und Herkunft, aktualisiere Empfängernamen aus dem jeweils
anderen Konto und berechne Duplikatfingerabdrücke neu. Geschlossene Konten,
abgeglichene Seiten, Nullbeträge, unvollständige Paare und Einzeländerungen
sind harte Fehler. Erfasse die Paaränderung als ein Auditereignis und ein
vollständiges Zwei-Seiten-Undo. Teste stabile IDs, Salden, Datum/Zweck,
Einzelpfadsperre, Undo und Fremdwährungskurse.

# Reproduzierbarer vollständiger offener Datenexport

Ergänze im Ablage-Menü und im Bereich `Import/Export` die Aktion
`Offenes Datenarchiv exportieren …`. Das Ziel ist ein neues Paket mit der
Endung `.finanzarchiv`; vorhandene Ziele, Symlink-Zielordner und andere
Endungen sind harte Fehler. Erzeuge zuerst per SQLite-Online-Backup einen
konsistenten, unabhängigen Snapshot in einem privaten versteckten
Zwischenordner. Die aktive Finanzdatei darf während des Exports weder
checkpointed noch fachlich verändert werden.

Das Paketformat besitzt Kennung
`de.pixelpuxel.finanzverwalter.open-data` und Versionsnummer 1. Schreibe
`data.json` mit jeder nicht internen SQLite-Tabelle, Spaltennamen und Zeilen,
`csv/<tabelle>.csv` als RFC 4180 mit UTF-8-BOM für dieselben Daten sowie
`schema.json` mit SQL-Typen und Primärschlüsselpositionen. Sortiere jede
Tabelle stabil nach ihrem vollständigen Primärschlüssel; Tabellen ohne
Primärschlüssel nach `rowid`. Bewahre UUIDs und Fremdschlüssel unverändert.
Kodierte Rest-BLOBs werden als Base64-Objekt beschrieben.

Exportiere `attachment_blobs.payload` nicht erneut in JSON oder CSV. Prüfe
zuerst deklarierte Größe und SHA-256, schreibe jeden deduplizierten Payload
unter `attachments/<sha256>.<erweiterung>` und ersetze das Feld in den
Tabellenexporten durch `relative_path`. Lasse gerätegebundene
`contract_documents.bookmark_data` sowie
`inventory_attachments.bookmark_data` ausdrücklich weg und dokumentiere
diese Auslassungen im Schema. Schreibe in `settings.json` ausschließlich eine feste
Whitelist für Darstellung, automatische Sicherung, Shortcuts,
Kontoblattansichten/-tabs/-sortierung, Importprofile und Matchingfenster.
Exportiere nie zuletzt verwendete Dateipfade, Security-Scoped Bookmarks,
Passwörter, Zugangsdaten oder Banking-/API-Token.

Ergänze eine menschenlesbare `README.txt`. Setze Paketordner auf `0700` und
Dateien auf `0600`. Erzeuge zuletzt `checksums.sha256` für jede andere Datei,
verschiebe den Zwischenordner atomar und validiere am endgültigen Ziel die
exakte Dateimenge sowie jede Prüfsumme erneut. Entferne bei jedem Fehler nur
eigene Zwischenartefakte. Teste vollständige Tabellenabdeckung, Beziehungen,
Splits, exakte Anhangsbytes, CSV-BOM und Escaping, Geheimnis-/Pfadausschluss,
Rechte, deterministische Wiederholung bei festem Zeitpunkt, Quellintegrität,
Zielschutz und das Fehlen liegengebliebener Zwischenordner.

Behandle `data.json` als autoritative Rekonstruktionsquelle und die CSV-Dateien
als verpflichtende offene Spiegel. Ergänze im Ablage-Menü und im Bereich
`Import/Export` den Rückimport in eine neue `.qdata`-Datei. Akzeptiere nur
Paketformat 1 und exakt die aktuelle Datenbankschemaversion. Prüfe vor dem
JSON-Lesen das vollständige SHA-256-Manifest, die exakte dokumentierte
Dateimenge, reguläre Dateien ohne Symlinks, sichere relative Pfade und feste
Grenzen für Gesamtgröße, Manifest, JSON, Schema, Einstellungen, Tabellen,
Spalten, Zeilen, BLOBs und Anhänge. Lehne unbekannte oder fehlende Tabellen,
Spalten, CSV-Spiegel und Zusatzdateien ab.

Erzeuge im Zielordner zunächst eine private neue Datenbank mit dem aktuellen
Schema. Rekonstruiere jede Anwendungstabelle innerhalb einer einzigen
Transaktion mit unveränderten Primär- und Fremdschlüsseln. Lade
Anhangspayloads ausschließlich vom aus SHA-256 und MIME-Typ erwarteten
relativen Pfad und prüfe Größe und Inhalts-Hash erneut. Vergleiche nach dem
Einfügen jede Tabellenzeilenzahl, führe `foreign_key_check` und
`integrity_check` aus und veröffentliche erst dann eine private `0600`-Datei
atomar am neuen Ziel. Überschreibe weder ein vorhandenes Ziel noch die aktive
Finanzdatei und entferne im Fehlerfall ausschließlich eigene
Zwischenartefakte. Öffne die neue Datei erst nach Erfolg und erstelle dabei
wie bei jedem Dateiwechsel eine Sicherung der bisherigen Datei. Übernimm
archivierte Oberflächeneinstellungen niemals ungefragt. Teste vollständigen
Tabellen-, Beziehungs-, Split-, Hierarchie-, Tag- und Anhangsrundlauf,
Quellunveränderlichkeit, Zielschutz, Rechte, fehlende Sidecars sowie die
Abweisung manipulierter Hashes, Pfad-Ausbrüche, Symlinks und selbst korrekt im
Manifest eingetragener Zusatzdateien.

Ergänze Buchungen um ein optionales farbiges Kennzeichen mit den stabilen
Werten `red`, `orange`, `yellow`, `green`, `blue` und `purple`. Migriere die
SQLite-Datenbank additiv auf Schema 40: `transactions.flag_color` ist nicht
NULL, nutzt für „ohne Kennzeichen“ den Leerstring, besitzt eine CHECK-Constraint
auf exakt diese Werte und einen partiellen Index für markierte Buchungen.
Altdaten aus Schema 39 müssen unverändert und ohne Kennzeichen erhalten bleiben.

Führe das Kennzeichen durch sämtliche Buchungspfade: Laden und Speichern,
Vorlagen, Duplikate, vollständige Undo-Snapshots, Sicherungen, Massenimport und
offenes Gesamtdatenarchiv. Zeige im Kontoblatt eine sortierbare, konfigurierbare
Spalte mit farbiger Fahne; migriere bestehende Spaltenkonfigurationen und
gespeicherte Ansichten einmalig um diese Standardspalte. Ergänze Buchungs- und
Splitbuchungseditor, Volltextsuche, Filter „alle/ohne/eine Farbe“, gespeicherte
Ansichten, CSV-/PDF-Kontenblattausgabe und die atomare Massenorganisation.
Kennzeichen-Massenänderungen müssen Schutzprüfung, Audit und vollständiges Undo
nutzen. Teste Schema-39→40, Persistenz, Suche, Vorlagen, Bulk-Änderung und Undo;
verwende für Zukunftsschema-Abweisungen ab dann Schema 41.

Erweitere die buchungsbasierte Berichtswerkstatt um einen vollständig
kombinierbaren Kennzeichenfilter. Speichere in `TransactionReportQuery`
optional die Menge der sechs Kennzeichenfarben und unabhängig davon, ob
unmarkierte Buchungen enthalten sind. `nil` muss aus Rückwärtskompatibilität
„alle Farben einschließlich ohne Kennzeichen“ bedeuten. Biete in der
Oberfläche Aktionen für alle, nur gekennzeichnete und jede einzelne Farbe
sowie einen unabhängigen Schalter für „ohne Kennzeichen“.

Führe diese Auswahl durch Query-Snapshot, Filteraktiv-Anzeige, Reset,
Filterzusammenfassung, versionierte Berichtsvorlagen, eigenständige
Berichtsfenster und Rückintegration. Da CSV, PDF, HTML, XLSX,
Zwischenablage und Systemdruck denselben unveränderlichen Snapshot verwenden,
müssen alle Ausgaben exakt dieselbe gefilterte Buchungsmenge zeigen. Teste
Farbauswahl, ausschließlich unmarkierte Buchungen, Vorlagenrundlauf und die
Dekodierung älterer Queries ohne das neue Feld.

Ergänze die buchungsbasierte Berichtswerkstatt um konfigurierbare
Detailspalten. Definiere einen stabil codierten
`TransactionReportDetailColumn` mit Datum, Konto, Empfänger,
Verwendungszweck, Memo, Kategorie, Klasse/Tags, Status, Kennzeichen, Betrag,
Währung und Splitstatus. Speichere die geordnete Auswahl optional als
`detailColumns` in `TransactionReportQuery`; ein fehlendes oder leeres Feld
muss rückwärtskompatibel auf Datum, Konto, Empfänger, Zweck, Kategorie,
Status und Betrag zurückfallen.

Führe die normalisierte Auswahl in `TransactionReportPresentation` des
unveränderlichen Snapshots. Die Oberfläche bietet Standard, alle und einzelne
Spalten, verhindert eine vollständig leere Tabelle und verwendet
`TableColumnForEach`. Vorlagen ab Definitionsversion 5, Außenfenster und
Rückintegration bewahren die Auswahl. CSV, PDF, HTML, XLSX und die beiden
Zwischenablage-Repräsentationen erzeugen Kopf und Werte ausschließlich aus
derselben Spaltenfolge; XLSX lässt Beträge numerisch, PDF verteilt die
verfügbare Breite gewichtet. Teste Query-/Vorlagenrundlauf, Legacy-Decodierung,
Kennzeichenübernahme sowie semantische und deterministische Ausgaben aller
Kanäle.

Mache die gespeicherte Spaltenreihenfolge in der Oberfläche tatsächlich
editierbar. Das Untermenü `Reihenfolge` bietet je sichtbarer Spalte „An den
Anfang“, „Nach links“, „Nach rechts“ und „Ans Ende“ und deaktiviert unmögliche
Randaktionen. Eine neu eingeblendete Spalte wird ans Ende angefügt; Ausblenden
bewahrt die relative Folge der übrigen Spalten und darf die letzte sichtbare
Spalte nicht entfernen. Kapsle Normalisierung, Sichtbarkeit und Verschieben in
deterministische, direkt testbare Fachfunktionen.
