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

Migrationen 1 bis 13, Konto-/Kategorie-/Buchungspersistenz, Splits, atomare
Transfers, QIF/CSV, Kontoabgleich, Sammelkontoblatt, Bericht, Backup,
validierte Wiederherstellung, Kategorisierungsregeln und ein erster
Serientermin-/Prognose-Slice sowie monatliche Kategorie-Budgets sind
implementiert. Zusätzlich ist ein rein lokaler Banking-Simulator mit
Zahlungsaufträgen und SCA-Zustandsautomat vorhanden. Die Testsuite umfasst
aktuell dreißig erfolgreiche
XCTest-Fälle. Debug- und Release-Build wurden
erfolgreich ausgeführt; der Release-Stand ist lokal installiert und sichtbar
geprüft. Details und Screenshots stehen in `Gedächtnis.md`.

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

Die Massenkategorisierung erhält eine Menge Buchungs-UUIDs und eine optionale
Zielkategorie. Prüfe vor jeder Mutation, dass alle UUIDs existieren, die
Kategorie aktiv ist und keine ausgewählte Buchung abgeglichen, umgebucht oder
gesplittet ist. Führe anschließend alle Kategorieänderungen samt Audit in
genau einer SQLite-Transaktion aus. Die Oberfläche zeigt zuvor Anzahl und
Summen getrennt nach Währung und verlangt eine zweite Bestätigung.

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
  werden. Wochenenden können unverändert, auf den nächsten oder den
  vorherigen Wochentag verschoben werden; Feiertage sind bis zu einem
  versionierten Kalender ausdrücklich nicht behauptet.
- Der XCTest-Apphost muss eine pro Prozess temporäre Finanzdatei öffnen.
  Automatisierte Tests dürfen die Produktivdatei weder migrieren noch
  verändern; prüfe dies zusätzlich durch identische SHA-256-Werte vor und
  nach der vollständigen Suite.

Für Empfänger und Klassen/Tags gilt reproduzierbar:

- `payees`, `payee_aliases`, `tags`, `transaction_tags` und `split_tags`
  werden ab SQLite-Migration 7 gespeichert.
- Der sichtbare Empfängertext bleibt für Importtreue erhalten; `payee_id`
  verknüpft optional die kanonische Empfängerakte.
- Aliase werden getrimmt, dedupliziert und getrennt vom kanonischen Namen
  gespeichert.
- Tags besitzen optionale Hierarchie, Farbe, Beschreibung und Aktivstatus.
- Hauptbuchungen und Splitzeilen besitzen unabhängige n:m-Tag-Zuordnungen.
- SmartFill filtert Name und Aliase, priorisiert Präfixe und danach die
  bisherige Verwendung; eine Auswahl übernimmt Name und Vorgaben erst im
  Editor und schreibt niemals unbemerkt.

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
