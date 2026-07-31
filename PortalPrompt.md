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
- Parse deutsche Eingaben über `Decimal`; runde explizit auf Cent.
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

Migrationen 1 bis 29 sowie die in diesem Dokument beschriebenen lokalen
Konto-, Buchungs-, Berichts-, Regel-, Banking- und Importkerne sind
implementiert. Die jüngste vollständige isolierte Abnahme umfasst 82
XCTest-Fälle: 81 bestanden, der private opt-in-Real-QIF-Test wurde ohne
temporären Pfad erwartungsgemäß übersprungen, 0 Fehler. Der private echte
2025-QIF-Test bestand zusätzlich separat mit einer danach gelöschten
temporären Kopie. Die Release-App ist lokal
installiert; die jüngste visuelle Abnahme bleibt bei gesperrtem Mac offen.
Details und frühere Screenshots stehen in `Gedächtnis.md`.

Migration 11 ergänzt `account_groups` und erweitert `accounts` um Kurzname,
Beschreibung, Gruppe, IBAN, BIC, maskierte Kontonummer, Inhaber,
Eröffnungsdatum, Kreditlimit, Onlinekennzeichen, vier getrennte
Einbeziehungsregeln, Abrufzeit, Banksaldo und Abrufstatus. Kontonamen sind
Pflicht, Kreditlimits nicht negativ, IBANs werden normalisiert und mit Mod 97
validiert, Gruppen müssen existieren. Kontengruppen besitzen Reihenfolge und
Aktivstatus. Die Kontenübersicht zeigt Gruppensummen, Saldo, verfügbaren Betrag
und Abrufstatus; der Editor kann bestehende Konten vollständig ändern.
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
- Geld als `Int64`-Minor-Units, Fälligkeiten als kalendarisches ISO-Datum.
- Monatsbasierte Rhythmen erhalten die Monatsende-Semantik, auch über den
  29. Februar eines Schaltjahres.
- Jede virtuelle Instanz trägt
  `schedule:<Serien-UUID>:<Unixzeit der Fälligkeit>` als Herkunftskennung.
- Die Vorschau filtert Herkunftskennungen, die bereits als echte erwartete
  Buchung vorhanden sind, damit kein realer Vorgang doppelt zählt.
- Der Prognosesaldo beginnt mit Eröffnungssaldo plus nicht stornierter,
  nicht erwarteter Buchungen bis heute und addiert erwartete sowie noch
  virtuelle Serientermine bis zum jeweiligen Stichtag.

Für Budgets gilt reproduzierbar:

- `budgets` und `budget_lines` werden ab SQLite-Migration 5 gespeichert.
- Ein Budget definiert Name, Startjahr, Startmonat, Währung und Aktivstatus;
  zwölf Monate können dadurch auch ein freies Geschäftsjahr abbilden.
- Ein Monatsplan ist pro Budget, Kategorie, Jahr und Monat eindeutig.
- Planwerte sind editierbare positive Minor-Units; das Ist wird ausschließlich
  aus nicht stornierten, nicht als Transfer verknüpften Buchungen berechnet.
- Ausgabenabweichung ist `Plan - abs(Ist)`, Einnahmenabweichung ist
  `Ist - Plan`.
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
- Noch offen sind die automatische Splitbuchung realer Raten, der
  Ist-Abgleich, Szenarien und der optionale Debt-Reduction-Planner.

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

Vor dem Mehrfachlöschen müssen alle ausgewählten IDs existieren und alle
ausgewählten Buchungen sowie beide Seiten betroffener Umbuchungen
unangetastet sein. Enthält die Menge eine abgeglichene Buchung, ändere
nichts. Zeige immer eine Bestätigung mit der Zahl der Buchungen. Lösche
danach die gesamte validierte Menge in genau einer SQLite-Transaktion und
schreibe Auditereignisse.

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
