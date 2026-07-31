# Gedächtnis – FinanzVerwalter-Desktopprojekt

Letzte Aktualisierung: 31.07.2026

## Auftrag

Im Ordner `/Users/gabrielschreiber/Documents/iPhone Apps/FinanzVerwalter` entsteht
eine vollständig neue, eigenständige Desktop-Finanzverwaltung. Das vorhandene
Projekt `Banking` und andere App-Projekte werden weder als Quellcodebasis noch
als UI-Vorlage verwendet.

Die fachliche Produktspezifikation liegt als externe Master-Datei außerhalb
des Repositorys vor.

Der verbindliche Produkt-, App-, Target- und Verzeichnisname ist
**FinanzVerwalter**. Die fremde Bezeichnung „Quicken“ darf ausschließlich als
sachlich erforderlicher Hinweis auf eine tatsächlich vorhandene
Datei-/Importkompatibilität erscheinen. FinanzVerwalter darf keine Verbindung,
Autorisierung oder Herkunft vom fremden Rechteinhaber nahelegen. Arbeitsleitplanke
ist § 23 Abs. 1 Nr. 3 in Verbindung mit Abs. 2 MarkenG; dies ist keine
Rechtsberatung.

## Verbindliche Arbeitsregeln

- Desktop-first, local-first und ohne Cloud-Anmeldung nutzbar.
- Neue Oberfläche in SwiftUI; deutsche Benutzertexte, englische Typnamen.
- Keine Drittanbieterabhängigkeiten ohne vorherige Rücksprache.
- Geldwerte nie als binäre Fließkommazahlen persistieren.
- Finanzielle Änderungen transaktional, validiert und auditierbar ausführen.
- Nach Änderungen kompilieren, relevante Tests ausführen und die Mac-App
  sichtbar prüfen.
- Andere Projekte bleiben unverändert.
- Zwischenstände und Sichtnachweise werden in den vereinbarten
  Telegram-Projektthread (Thread-ID 894) gesendet; Zugangsdaten werden nie
  ausgegeben oder gespeichert.

## Architekturentscheidungen

- Native macOS-App statt Erweiterung einer bestehenden iPhone-/Banking-App.
- SwiftUI und AppKit-Systemintegration ohne externe Abhängigkeiten.
- SQLite aus dem Betriebssystem, WAL-Modus und versionierte Migrationen.
- Geldbeträge als `Int64` in Minor-Units; Eingabe über `Decimal`.
- Mindestfenster 960 × 640, Standardfenster 1380 × 860.
- Klassisches, dichtes Desktop-Bedienmodell mit Menü, Werkzeugleiste,
  Kontenleiste, Kontoblatt und Statuszeile.

## Bisher umgesetzt

- vollständig neues Xcode-Projekt `FinanzVerwalter.xcodeproj`
- macOS-App-Target und Unit-Test-Target
- App-Einstieg mit Desktop-Kommandos für neue Buchung, Suche und Abgleich
- Grundmodelle für Finanzdatei, Konten, Kategorien, Buchungen und Splits
- centgenauer `Money`-Typ mit deutscher Eingabe und Ausgabe
- Split-Invariante im Domänenmodell
- versioniertes SQLite-Schema mit WAL, Foreign Keys und elf Migrationen
- Tabellen für Finanzdatei, Konten, Kategorien, Buchungen, Splits,
  Importpakete und append-only Auditereignisse
- atomare Konto-, Kategorie-, Buchungs-, Import- und Transfer-Use-Cases
- Import-Idempotenz über SHA-256 des vollständigen CSV-Pakets
- SQLite-Backup über die Backup-API mit anschließender Integritätsprüfung
- klassische Desktop-Shell mit Menü, Werkzeugleiste, Navigation,
  Kontenleiste, Arbeitsfläche und Statuszeile
- Cockpit mit Nettovermögen, Konten, Einnahmen-/Ausgaben-Chart, letzten
  Buchungen und lokalem Systemstatus
- Kontenübersicht, Kontoanlage und vollständige Kontobearbeitung
- frei verwaltbare, sortierbare und deaktivierbare Kontengruppen
- Kontostammdaten mit Kurzname, Beschreibung, 13 Kontotypen, Währung,
  Inhaber, Institut, validierter IBAN, BIC, maskierter Kontonummer,
  Eröffnungsdatum und Kreditlimit
- lokale/Online-Kennzeichnung, Abrufstatus, letzter Abruf und letzter
  Banksaldo als vorbereitete Adapterfelder
- getrennte Einbeziehung eines Kontos in Vermögen, Budget, Berichte und
  Prognose; die jeweiligen Berechnungen beachten diese Schalter
- Gruppensummen werden je Währung getrennt dargestellt; das Nettovermögen
  summiert ohne vorhandene FX-Tabelle ausschließlich die Basiswährung und
  weist Fremdwährungskonten sichtbar aus
- dichtes Kontoblatt mit Kontoauswahl, Status, Empfänger, Zweck, Kategorie,
  Konto und Betrag
- Buchungseditor, Suche, Kontextbearbeitung und Löschen
- eigener Umbuchungsdialog; zwei Kontoseiten werden atomar gespeichert
- Einnahmen-/Ausgaben-Kategoriebericht
- CSV-/TSV-Import mit Vorschau und ausdrücklicher Übernahme
- Kategorienverwaltung und Datenbank-Integritätsprüfung
- reproduzierbarer Demo-Sichtprüfmodus ausschließlich über `-demo`
- SQLite-Migration 2 mit dokumentierten Kontoabgleichen
- Splitdialog mit beliebig ergänzbaren Zeilen, Kategorie, Notiz,
  Restbetragsanzeige und „Rest zuweisen“
- QIF-Einzelkontoimport mit Empfänger, Memo, Referenz, Kategorien und
  exakten Splits
- automatische Erkennung vollständiger Mehrkonten-QIF-Pakete; solche
  Dateien können nicht mehr versehentlich in ein einzelnes Zielkonto
  importiert werden
- Paketvorschau mit Konten, neuen Ober-/Unterkategorien, Buchungsanzahl,
  Warnungen und den ersten 100 Buchungen
- atomarer QIF-Paketimport von Konten, hierarchischen Kategorien,
  Buchungen und Splits mit SHA-256-Idempotenz
- Depot-, Klassen- und Merkpostenbereiche werden gezählt und sichtbar
  ausgelassen, bis ihr jeweiliges Fachmodell verlustfrei unterstützt wird
- Kontoabgleich nur bei centgenau passendem Auszugssaldo
- abgeglichene Buchungen gegen unbeabsichtigte Änderungen geschützt
- Sammelkontoblatt mit allen Konten, Status, Heute-Grenze und Summe ohne
  Umbuchungen
- validierte Wiederherstellung mit automatischer Sicherheitskopie der
  bisherigen Finanzdatei
- deterministische Kategorisierungsregeln mit Priorität, Aktivstatus,
  Empfänger-/Zweck-/Betragsbedingungen, Vorschau und geschützter Anwendung
- SQLite-Migration 3 für persistente Kategorisierungsregeln
- SQLite-Migration 4 für persistente regelmäßige Vorgänge
- tägliche, wöchentliche, zweiwöchentliche, monatliche, zweimonatliche,
  quartalsweise, halbjährliche und jährliche Rhythmen
- stabile Monatsende-Berechnung über Monats- und Schaltjahresgrenzen
- Editor für regelmäßige Vorgänge mit Konto, Kategorie, Betrag, Fälligkeit,
  optionalem Ende, Aktion, Erinnerungsfrist und Aktivstatus
- Liquiditätsvorschau mit 30/90/180/365-Tage-Horizont, Herkunft je Position
  und projiziertem Kontostand
- Herkunftskennungen verhindern die doppelte Prognose bereits als erwartete
  Buchung materialisierter Serientermine
- SQLite-Migration 5 für mehrere benannte Kalender- oder
  Geschäftsjahresbudgets und monatliche Kategoriepläne
- Budgetansicht mit Ausgabenplan, unveränderlichem Ist aus Buchungen,
  centgenauer Abweichung, gerundetem Erfüllungsgrad und Kategorie-Drill-down
- Budgeteditor für monatlichen Plan sowie positiven und optional negativen
  Roll-over je Kategorie
- SQLite-Migration 6 für lokale Zahlungsaufträge mit eindeutiger
  Idempotenzkennung und versioniertem Status
- SEPA-, Echtzeit- und Terminüberweisungsentwürfe mit IBAN-Mod-97-Prüfung,
  Pflichtfeldern, Ausführungsdatum und End-to-End-ID
- vollständig lokaler Banking-Simulator mit der SCA-Kette
  `initiated -> challenge_received -> awaiting_user -> submitted ->
  accepted/rejected/unknown`
- unveränderliche Auftragszusammenfassung und erneute Bestätigung vor der
  simulierten Initialisierung
- Freigabecode bleibt ausschließlich im Arbeitsspeicher und wird weder
  persistiert noch protokolliert
- angenommener Auftrag materialisiert atomar genau eine vorgemerkte Buchung;
  `unknown` kann nicht automatisch oder per Zustandswechsel neu gesendet werden
- SQLite-Migration 7 für Empfängerakten, Aliase, hierarchische Klassen/Tags,
  Buchungs-Tags und eigene Tags je Splitzeile
- Empfängerakte mit kanonischem Namen, Aliasen, Kontakt- und Bankdaten,
  Standardkategorie, bevorzugtem Konto, Notiz und Aktivstatus
- SmartFill-Auswahl im Buchungseditor normalisiert den sichtbaren Empfänger
  und übernimmt vorhandene Vorgaben ohne selbstständig zu speichern
- unabhängige Mehrfach-Tags auf Hauptbuchung und Splitzeilen; Tags fließen
  in die globale Suche ein
- SQLite-Migration 8 für Wertpapierstammdaten, Vermögensklassen,
  Allokationen, Transaktionen, einzelne Anschaffungslots, Lot-Verbräuche
  und historische Kurse
- Stückzahlen als `Int64` mit sechs Dezimalstellen; Kurse und Kostenbasis
  ohne binäre Fließkommazahlen
- atomare Käufe und FIFO-Teilverkäufe mit Gebühren, Steuern,
  Reststücken, fortgeschriebener Restkostenbasis und realisiertem Gewinn
- Depotpositionen mit Bestand, Kostenbasis, letztem Kurs, Marktwert und
  unrealisiertem Gewinn sowie Transaktionshistorie
- Vermögensklassen-Zuordnung kann nur mit exakt 100 % gespeichert werden
- Verkäufe über den vorhandenen Bestand werden vor jeder Mutation
  abgewiesen; Short-Verkäufe sind im aktuellen UI ausdrücklich deaktiviert
- SQLite-Migration 9 für Darlehen, historisierte Zinssätze,
  Sondertilgungen, vorbereitete Ist-Zuordnungen, Vermögenswerte und
  datierte Bewertungen
- centgenauer Tilgungsplan mit Rate, Tilgung, Zins, Gebühr,
  Sondertilgung und Restschuld je Fälligkeit
- Zinsänderungen gelten ab einem expliziten Datum; die Berechnung nutzt
  einen gregorianischen UTC-Kalender und bleibt über Sommerzeitgrenzen stabil
- Vermögenswerte für Immobilien, Fahrzeuge, Sammlerstücke und Sonstiges
  mit Kaufwert, aktuellem Wert, Wertverlauf und optional verknüpftem Kredit
- Kredit- und Vermögensübersicht mit aggregierter Restschuld, aktuellem
  Vermögen und kreditbereinigtem Nettoanteil
- persistenter Erscheinungsbild-Schalter für Hell, Dunkel und System;
  die weitere Sichtprüfung erfolgt im Light Mode
- SQLite-Migration 10 für Verträge, Dokumentmetadaten, Inventargegenstände
  und Anhangsmetadaten
- SQLite-Migration 11 für Kontengruppen und erweiterte Kontostammdaten
- Verträge mit Anbieter, Nummer, Typ, Beginn, Mindestlaufzeit,
  Verlängerung, Kündigungsfrist, Zahlfrequenz, Konto, Kategorie,
  Erinnerung und erwarteten Jahreskosten
- Inventar mit Kategorie, Raum, Kauf-/aktuellem/Versicherungswert,
  Händler, Seriennummer, Garantieende und Notiz
- eigener Hauptbereich „Kategorien“ mit Ober-/Unterkategorien, vollständigen
  Pfaden, Farbe, Art und Aktivstatus
- zyklische Kategoriehierarchien sowie Eltern anderer Einnahmen-/Ausgabenart
  werden vor jeder Speicherung abgewiesen
- Buchungs-, Split-, Regel-, Empfänger-, Vertrags- und Serientermindialoge
  zeigen Kategorien als vollständigen Pfad

## Noch offen

- vollständige Regelketten mit Stop-Logik und Editor für Betragsgrenzen
- tiefere Kategorieverwaltung, MwSt.- und Steuerzuordnungen sowie
  Auswertungsfilter für Klassen/Tags
- benutzerdefinierte Rhythmen, Feiertags-/Bankarbeitstagsregeln,
  einzelne Serienausnahmen und automatische Materialisierung
- OFX-/camt-Import sowie offene JSON-Gesamtexporte
- mehrere frei wählbare Finanzdateien
- Budgetkopie/-umbenennung/-löschung, Jahreswerte, Roll-over-Reserve und
  Budgetberichte
- Monats-/Wochen-Kalender, Drag-and-drop und Was-wäre-wenn-Szenarien
- read-only Banking-Adapter, Umsatz-/Saldoabruf, FinTS/PSD2-Kontakte,
  Daueraufträge, Lastschriften, Sammelaufträge und ISO-20022-Dateiformate
- weitere Wertpapierarten, spezifische Lot-Auswahl, Durchschnittsmethode,
  Short-Positionen, Kapitalmaßnahmen, Dividenden, TWR/IRR und Kursimport
- automatische Ratensplitbuchung und Ist-Abgleich, Kredit-Szenarien,
  Debt-Reduction-Planner und Freistellungsaufträge
- vollständige Accessibility-, Performance-, Security- und UI-Testabdeckung
- Release-Build, signierte Auslieferung und finale Abweichungsdokumentation

## Verifikationsstand

- Debug- und optimierter Release-Build am 31.07.2026 erfolgreich
- 23 XCTest-Fälle erfolgreich, davon ein lokaler Realdatei-Abnahmetest:
  - deutsche Geldbeträge und Rundung
  - Split-Invariante
  - Migration, Persistenz und Saldo
  - atomarer Transfer
  - idempotenter CSV-Import
  - unabhängiges, valides Backup
  - QIF-Import mit exakten Splits
  - QIF-Mehrkontenpaket mit Konten, Kategoriehierarchie, normalen
    Buchungen, sichtbar ausgelassenem Depotbereich, atomarem Commit und
    Dublettenabwehr
  - externe QIF-Realdatei: Mehrkontenerkennung, keine abgelehnte normale
    Kontobuchung, vollständiger temporärer Commit und SQLite-Integrität
  - Kontoabgleich und Schutz abgeglichener Buchungen
  - Abweisung ungültiger Sicherungen
  - deterministische Kategorisierungsregel mit Schutz abgeglichener Buchungen
  - persistenter Monatsende-Serientermin über das Schaltjahr 2024 und
    Ausschluss einer bereits materialisierten Herkunft aus der Prognose
  - Geschäftsjahresbudget April bis März, persistenter Monatsplan,
    Abweichung und dezimal gerundeter Erfüllungsgrad
  - IBAN-Prüfsumme, Zahlungsidempotenz, vollständiger SCA-Zustandsautomat,
    einmalige Buchungsmaterialisierung und Neuversandverbot bei `unknown`
  - Empfänger-/Alias-Roundtrip, Tag-Hierarchie sowie Mehrfach-Tags auf
    Buchung und einzelnen Splitzeilen
  - Festkomma-Stückzahlen, exakt 100-%-Allokation, zwei FIFO-Lots,
    Teilverkauf, Restkostenbasis, realisierter/unrealisierter Gewinn und
    unveränderter Bestand nach abgewiesenem Überverkauf
  - Darlehen mit versioniertem Zins über eine Sommerzeitgrenze,
    Sondertilgung, centgenauer Restschuldinvariante, Wertverlauf und
    kreditbereinigtem Nettoanteil
  - Vertragsjahreskosten, rollierende Verlängerung, Kündigungsfrist und
    persistenter Inventar-/Versicherungswert
  - persistente Unterkategorien sowie Abweisung von Zyklen und
    artfremden Oberkategorien
  - Kontengruppen, vollständiger Metadaten-Roundtrip, IBAN-Normalisierung
    und -Abweisung sowie wirksamer Ausschluss aus Berichten
  - gezielte Migration einer vorhandenen Schema-10-Finanzdatei auf
    Migration 11 unter Erhalt des Bestandskontos und sicheren Standardwerten
  - keine unzulässige Addition eines USD-Kontos zum EUR-Nettovermögen ohne
    dokumentierten Wechselkurs
- installiert unter `/Users/gabrielschreiber/Applications/FinanzVerwalter.app`
- installierte App mit `-demo` gestartet
- Cockpit und Kontoblatt über Accessibility-Struktur und sichtbaren
  Screenshot geprüft
- Screenshots:
  - `build/Screenshots/01-cockpit.png`
  - `build/Screenshots/02-kontoblatt.png`
  - `build/Screenshots/03-sammelkontoblatt.png`
  - `build/Screenshots/04-splitdialog.png`
  - `build/Screenshots/05-split-gespeichert.png`
  - `build/Screenshots/06-kalender-prognose.png`
  - `build/Screenshots/07-budget.png`
  - `build/Screenshots/08-banking-simulator.png`
  - `build/Screenshots/09-empfaenger-tags.png`
  - `build/Screenshots/10-depot-fifo.png`
  - `build/Screenshots/11-kredite-vermoegen.png`
- Zwischenstände samt Screenshots im Telegram-Projektthread
  (Thread-ID 894) gepostet
- lokales Git-Repository auf Branch `main`; öffentlicher bereinigter
  Stammcommit `0ce0c89`
- Splitdialog über die installierte Release-App mit einem Betrag von
  -100,00 EUR und zwei Zeilen von -60,00/-40,00 EUR funktional geprüft;
  Rest 0,00 EUR und Speicherung erfolgreich
- Kalender-/Prognoseansicht der installierten Release-App zeigt im
  isolierten Demo-Modus drei aktive Serien und 16 erwartete Termine über
  mehrere Monatsgrenzen; der vollständige Serientermin-Editor wurde über
  seine Accessibility-Struktur geprüft
- Budgetansicht der installierten Release-App zeigt ein Haushaltsbudget mit
  Plan, Ist, Abweichung und korrekten Prozentwerten; der Drill-down weist
  den Planwert, Roll-over-Schalter und die zugrunde liegende EDEKA-Buchung
  als nicht editierbares Ist aus
- Banking-Simulator der installierten Release-App über Accessibility und
  Screenshot geprüft; ein neuer Auftrag über 12,34 EUR wurde vom Entwurf
  über Bestätigung, Challenge, Freigabecode und Übermittlung bis
  `accepted` geführt und erzeugte genau eine vorgemerkte Buchung
- der bei der Sichtprüfung verwendete simulierte Freigabecode `123456`
  wurde anschließend nachweislich nicht in der isolierten Demo-Datenbank
  gefunden
- Einstellungen zeigen die EDEKA-Empfängerakte mit zwei Aliasen und zwei
  aktive Tags; Empfängereditor sowie Buchungseditor mit SmartFill-Auswahl
  und beiden Tag-Umschaltern wurden über Accessibility sichtbar geprüft
- Depotansicht der installierten Release-App zeigt zwei Positionen mit
  1.885,00 EUR Marktwert, 1.673,57 EUR Kostenbasis und 211,43 EUR
  unrealisiertem Gewinn; Wertpapierhistorie, 100-%-Allokationseditor und
  Kauf-/Verkaufseditor wurden sichtbar geprüft
- Kreditansicht der installierten Release-App zeigt ein Darlehen mit
  300.000,00 EUR Ursprung, 269.411,37 EUR aktueller Restschuld, 290
  berechneten Raten und einer datierten Sondertilgung; die Vermögensansicht
  zeigt 455.000,00 EUR aktuellen Immobilienwert und 185.588,63 EUR
  kreditbereinigten Nettoanteil
- GitHub-Repository `https://github.com/pixelpuxel/FinanzVerwalter` ist
  öffentlich und als `origin` eingerichtet. Die erreichbare Historie enthält
  ausschließlich den bereinigten FinanzVerwalter-Stand; Zugangsdaten stehen
  weder in Remote-URL noch Projektdateien.
- reale, ausschließlich extern gelesene ISO-8859-QIF-Datei als
  Migrations-Use-Case analysiert: Mehrkontenpaket mit 4.565 Datensätzen,
  97 Kontoblöcken, Kategorien, Klassen, Vorlagen und mehreren Kontotypen.
  Die Datei wird nicht versioniert. Für die lokale Xcode-Abnahme wurde eine
  zugriffsbeschränkte Kopie ausschließlich unter `/tmp` verwendet und danach
  entfernt. Der Produktionsparser erkannte das Mehrkontenpaket, lehnte keine
  normale Kontobuchung ab, übernahm es in eine wegwerfbare Datenbank und
  bestand anschließend `PRAGMA integrity_check`.
- vollständige Soll-Ist-Prüfung gegen die Masterdatei liegt in
  `docs/Anforderungsmatrix.md`; offene Punkte werden nicht als fertig
  dargestellt. Architekturentscheidungen stehen unter `docs/adr/`.
- Kontoblatt um Konto-, Status-, Kategorie- und Zeitraumfilter,
  Mehrfachauswahl, währungsgetrennte sichtbare Summen und eine zweistufig
  bestätigte Massenkategorisierung erweitert. Die Persistenz prüft die
  gesamte Auswahl vorab und ändert atomar nichts, sobald eine abgeglichene
  Buchung, Umbuchung oder Splitbuchung enthalten ist.
- Kategorieanzeigen im Konto- und Sammelkontoblatt verwenden den vollständigen
  Hierarchiepfad. Lange Pfade bleiben einzeilig, werden in der Mitte gekürzt
  und sind vollständig als Tooltip verfügbar; Splitbuchungen führen alle
  unterschiedlichen Splitpfade auf.
- 25 XCTest-Fälle einschließlich Atomaritäts- und Kategoriepfadtest bestehen
  ohne Fehler. Die vollständige Abnahme mit der externen realen QIF-Datei
  besteht ebenfalls 25/25.
- Der reale QIF-Bestand wurde auf ausdrücklichen Wunsch ausschließlich in die
  lokale normale Finanzdatei importiert: 97 Konten, 782 Kategorien und 2.170
  Buchungen; `PRAGMA integrity_check` meldet `ok`. Vor dem Erstimport entstand
  lokal `Vor QIF-Erstimport 2025.qbackup`. Weder Quelldatei noch lokale
  Finanzdatei oder Sicherung liegen im Repository.
- SQLite-Migration 12 legt neun fachliche Standardkontengruppen an und ordnet
  jedes bisher ungruppierte Konto anhand seines Kontotyps zu. Der
  Mehrkonten-QIF-Import weist dieselben Gruppen bereits beim Commit zu.
  Die lokale Realdatei wurde vor der Migration gesichert und danach mit
  Schema 12 geprüft: 97 von 97 Konten gruppiert, Integrität `ok`.
- Konto- und Sammelkontoblatt zeigen direkt rechts neben dem Betrag einen
  laufenden, kontenweisen Saldo. Die Berechnung beginnt mit dem
  Konto-Eröffnungssaldo, sortiert deterministisch nach Buchungsdatum und UUID
  und verändert sich durch stornierte Buchungen nicht.
- Der gemeinsame, persistierte Zeilenmodus schaltet zwischen 20 Pixel hoher
  Einzeile und 38 Pixel hoher Zweizeile um. Die Zweizeile kann Wertstellung,
  Memo, Referenz und Tags aufnehmen; feste Höhen verhindern Layoutflattern
  bei großen realen Kontenblättern.
- Build-for-testing und Release-Build bestehen. 26 XCTest-Fälle einschließlich
  laufender-Saldo-, Migration-, QIF-, Atomaritäts- und Kategoriepfadtest
  laufen fehlerfrei; die externe echte QIF-Datei besteht ebenfalls 26/26.
- Die installierte Release-App wurde im Light Mode sichtbar geprüft. Der
  Spaltenkopf `Saldo` steht rechts von `Betrag`, Einzeilig und Zweizeilig
  lassen sich umschalten, und die Sidebar enthält unter anderem die neue
  Gruppe `Kreditkarten`. Screenshot:
  `build/kontenblatt-saldo-zweizeilig.png`.
- Dieser verifizierte Zwischenstand wurde mit dem Screenshot im vereinbarten
  Telegram-Projektthread 894 als Nachricht 931 veröffentlicht.
- Die offizielle Funktionsrecherche zu Berichten und Drucken ist in
  `docs/Berichtswerkstatt.md` in ein reproduzierbares Query-, Snapshot-,
  Drill-down- und Ausgabeziel überführt. Der bestehende Kategoriebericht
  bleibt ausdrücklich nur ein Teilstand.
- Der erste Berichtswerkstatt-Slice ist implementiert. Eine unveränderliche
  Live-Query kombiniert Zeitraum, Konten/Gruppen, Kategorieunterbäume,
  Klassen/Tags, Empfänger, Status, absolute Betragsspanne, Volltext,
  Währungen sowie explizite Schalter für Transfers, Splitauflösung,
  ausgeblendete und von Berichten ausgeschlossene Konten.
- Splitbuchungen werden entweder ausschließlich als Gesamtbuchung oder
  ausschließlich als einzelne Splitfakten ausgewertet. Gruppen nach
  Kategorie, Empfänger, Konto oder Klasse/Tag bleiben währungsgetrennt und
  referenzieren ihre Fakten für den Buchungs-Drill-down.
- 28 XCTest-Fälle bestehen. Die reale 2025-QIF-Abnahme führt alle 2.170
  Buchungen durch die Berichtspipeline und prüft für jede Buchung, dass die
  Summe ihrer erzeugten Fakten exakt dem Originalbetrag entspricht.
- Die installierte Release-App zeigte 2.313 Auswertungspositionen aus dem
  realen Bestand. Der sichtbare Volltextfilter `Grundsteuer` reduzierte die
  Live-Auswertung auf 68 Positionen und zeigte getrennte vollständige
  Immobilien-Kategoriepfade. Ein gewählter Pfad lieferte ausschließlich seine
  13 zugrunde liegenden Buchungs-/Splitpositionen. Screenshot:
  `build/berichtswerkstatt-drilldown.png`.
- Dieser Berichtswerkstatt-Stand wurde mit dem Screenshot im
  Telegram-Projektthread 894 als Nachricht 932 veröffentlicht.
- Migration 13 speichert versionierte Berichtsvorlagen als Query-JSON mit
  eindeutigem Namen. Persistenz, Aktualisierung und Löschung sind getestet
  und auditiert.
- Der CSV-Exporter schreibt denselben Snapshot mit Metadatenblock, wählbarem
  Semikolon/Komma/Tabulator, UTF-8 oder ISO-8859-1, deutschem Minor-Units-
  Zahlenformat und korrektem Quote-/Zeilenumbruch-Escaping. Ein bytegenauer
  Golden-Test schützt das Format.
- 30 XCTest-Fälle einschließlich Vorlagen-Roundtrip und CSV-Golden-Test
  bestehen zusammen mit der vollständigen realen 2025-QIF-Abnahme.
- Vor der lokalen Schema-13-Migration wurde
  `Vor Migration 13 Berichtsvorlagen.qbackup` erstellt und mit Schema 12,
  97 Konten, 2.170 Buchungen und Integrität `ok` geprüft. Die migrierte
  Finanzdatei meldet Schema 13 und Integrität `ok`.
- In der installierten Release-App wurde die Vorlage
  `Gesamt nach Kategorie` gespeichert. Nach einem abweichenden
  `Grundsteuer`-Volltextfilter stellte `Vorlage laden` den gespeicherten
  Gesamtbericht mit 2.313 Positionen wieder her. Der CSV-Exportdialog öffnete
  mit `Gesamt-nach-Kategorie.csv` und wurde ohne Testdatei im Benutzerordner
  geschlossen.
- Der Vorlagen-/CSV-Stand wurde mit `build/berichtsvorlage-csv.png` im
  Telegram-Projektthread 894 als Nachricht 933 veröffentlicht.
- Der PDF-Exporter erzeugt denselben unveränderlichen Berichtssnapshot als
  A4-Hoch- oder Querformat. Titel, Zeitraum, Filter, Erstellungszeit,
  Basiswährung, gruppierte Übersicht, Buchungs-/Splitzeilen, wiederholte
  Tabellenköpfe und Seitenzahlen sind Bestandteil des Dokuments.
- Ein synthetischer Referenzbericht mit acht Gruppen und 80 Fakten ergab fünf
  Seiten. PDFKit öffnete ihn erneut und prüfte semantische Inhalte; Poppler
  meldete A4-Querformat und renderte erste, mittlere und letzte Seite. Die
  Sichtprüfung zeigte keine abgeschnittenen Tabellen oder überlaufenden
  Seiten.
- Die vollständige lokale Abnahme besteht nun aus 31 XCTest-Fällen. Auch mit
  der ausschließlich extern gelesenen 2025-QIF-Datei bestehen 31/31:
  97 Konten, 2.170 normale Buchungen, keine abgelehnte Buchung.
- Der Release-Build mit PDF-Ausgabe wurde unter
  `~/Applications/FinanzVerwalter.app` installiert und ad hoc signiert. Die
  direkte UI-Sichtprüfung dieses installierten Builds steht noch aus, weil
  der Mac beim Installationsabschluss gesperrt war.
- Die gerenderte erste PDF-Seite und der grüne 31/31-Teststand wurden im
  Telegram-Projektthread 894 als Nachricht 934 veröffentlicht.
- Konto- und Sammelkontoblatt erzeugen ihre Spalten nun datengetrieben.
  Datum, Wertstellung, Belegnummer, Status, Empfänger, Verwendungszweck,
  Kategorie, Klasse/Tags, Konto, Betrag und Saldo können vollständig ein-
  oder ausgeblendet werden; mindestens eine Spalte bleibt sichtbar. Beide
  Kontenblätter teilen dieselbe dauerhafte Spaltenauswahl.
- Benannte Kontoblatt-Ansichten speichern Zielkonto, Status- und
  Kategoriefilter, Zeitraum einschließlich eigener Grenzen, Ein-/Zweizeile
  und sichtbare Spalten. Gleichnamiges Speichern aktualisiert die vorhandene
  Ansicht; fehlende Konten werden ignoriert und fehlende Kategorien fallen
  auf `Alle Kategorien` zurück.
- Die Präferenzdekodierung ist fehlertolerant und verwendet bei leerem oder
  beschädigtem Spaltensatz alle Standardspalten. Der deterministische
  Roundtrip ist als 32. XCTest-Fall abgedeckt.
- Die vollständige externe 2025-QIF-Abnahme besteht mit 32/32 Tests:
  97 Konten, 2.170 Buchungen, keine abgelehnte normale Buchung.
- Für echte dynamische SwiftUI-Tabellenspalten wurde das Mindestziel
  dokumentiert von macOS 14.0 auf 14.4 angehoben; der Zielrechner läuft auf
  macOS 26. ADR 0004 hält die Entscheidung und ihre Folgen fest.
- Der optimierte Release-Build wurde erfolgreich erstellt, unter
  `~/Applications/FinanzVerwalter.app` installiert und ad hoc signiert.
  Schema 13 und die reale Finanzdatei blieben mit 97 Konten, 2.170 Buchungen
  und Integrität `ok` unverändert. Die visuelle UI-Abnahme wartet weiterhin
  auf das Entsperren des Mac.
- Der Zahlungsverkehr exportiert einzelne SEPA-, Termin- und
  Echtzeitüberweisungen als `pain.001.001.09`. Die zeitabhängigen Angaben
  sind im Regelpaket `EPC-SCT-2025-V1.0` mit Gültigkeitsbeginn 05.10.2025
  und Quelle `EPC132-08 SCT C2PSP IG 2025 V1.0` gekapselt.
- Der Writer prüft Auftraggebername und -IBAN, EUR, BIC, Betragsgrenze,
  EPC-Längen und Slash-Regeln. Er schreibt kontrollsummengenaue
  Minor-Units, `SLEV`, `INST` bei Echtzeit, `NOTPROVIDED` ohne
  Auftraggeber-BIC und lässt eine fehlende optionale Empfängerbank weg.
- Als Retry-Schutz ist der Initiierungsexport nur für `draft` auf einem
  nicht geschlossenen Auftraggeberkonto erlaubt. Insbesondere kann ein
  Auftrag mit unbekanntem oder terminalem Status nicht erneut exportiert
  werden.
- Zwei gezielte XCTest-Fälle prüfen deterministische Bytes, XML-Escaping,
  Kernelemente und Negativfälle. Eine aus demselben Test erzeugte
  Beispieldatei bestand zusätzlich `xmllint` gegen eine öffentlich
  zugängliche Kopie des generischen `pain.001.001.09`-XSD. Der offizielle
  EPC-ZIP-Server antwortete bei automatisiertem Abruf mit HTTP 403; die
  Geschäftsvorgaben wurden deshalb direkt anhand der offiziellen
  EPC-Dokumente geprüft und nicht als XSD-Nachweis ausgegeben.
- Die Gesamtregression besteht mit 33 regulären XCTest-Fällen; die opt-in
  ausgeführte reale 2025-QIF-Abnahme bestand zusätzlich mit 97 Konten,
  776 Kategorien, 2.170 Buchungen und 0 verworfenen Buchungen.
- Der optimierte Release-Build mit pain.001-Export ist unter
  `~/Applications/FinanzVerwalter.app` installiert und ad hoc signiert.
  Die produktive Finanzdatei blieb auf Schema 13, 97 Konten und 2.170
  Buchungen bei Integrität `ok`. Das vorherige Bundle liegt im ignorierten
  Pfad `build/FinanzVerwalter-vor-pain001-20260731-0847.app`. Nach Ergänzung
  des Entwurfs-/Wiederholungsschutzes wurde der Release erneut gebaut,
  installiert und signaturgeprüft; der unmittelbar vorherige Stand liegt
  zusätzlich unter
  `build/FinanzVerwalter-vor-pain001-retryschutz-20260731-0855.app`.
- Der XML-/Teststand wurde mit der echten erzeugten XML-Vorschau im
  Telegram-Projektthread 894 als Nachricht 935 veröffentlicht. Die
  Computer-Use-Abfrage lief bei weiterhin gesperrtem Mac in ein Timeout;
  die visuelle Prüfung des Exportknopfs und Dateidialogs bleibt deshalb
  offen und wird nicht als erledigt behauptet.
- Migration 14 ergänzt eigenständige Dauerauftragsvorlagen und eine
  unveränderliche, pro Fälligkeit eindeutige Ausführungshistorie.
  Auftraggeberkonto, Empfänger, IBAN/BIC, EUR-Betrag, Zweck, Frequenz,
  optionales Enddatum und Wochenendverschiebung werden validiert.
- Aktive Daueraufträge können pausiert, fortgesetzt oder terminal beendet
  werden. Jede offene Fälligkeit wird nach ausdrücklicher Bestätigung
  atomar als Terminüberweisungsentwurf plus Historienzeile erzeugt oder
  terminal übersprungen. Ein Retry liefert denselben Entwurf; eine
  Vorlagenänderung verändert alte Entwürfe nicht, und Zurückdatieren hinter
  verarbeitete Fälligkeiten ist gesperrt.
- Der neue Test deckt Samstag-zu-Montag-Verschiebung, genau-einmalige
  Materialisierung, unveränderte Altinstanz nach Vorlagenänderung,
  Überspringen, automatisches Ende und Reaktivierungsschutz ab. Damit
  bestehen 34 reguläre XCTest-Fälle sowie die separate echte QIF-Abnahme
  mit 97 Konten, 776 Kategorien, 2.170 Buchungen und 0 verworfenen
  Buchungen.
- Bei der Abnahme zeigte sich, dass der XCTest-Apphost bislang die
  Produktivdatei öffnete und dadurch die additive Schema-14-Migration vor
  der geplanten Sicherung ausführte. Konten- und Buchungsdaten blieben
  unverändert und die Integrität war `ok`; die neuen Tabellen waren leer.
  Der Testhost verwendet nun zwingend eine temporäre Datei. Ein kompletter
  Testlauf ließ den SHA-256-Wert der Produktivdatei bytegenau unverändert.
- Für den Rückweg wurde aus dem unveränderten Schema-14-Stand ohne
  Dauerauftragsdaten die validierte Datei
  `Rollback Schema 13 vor Dauerauftraegen.qbackup` erzeugt: Schema 13,
  97 Konten, 2.170 Buchungen, Integrität `ok`. Die zusätzliche
  Schema-14-Sicherung `Vor Migration 14 Dauerauftraege.qbackup` ist
  ebenfalls valide; beide liegen ausschließlich außerhalb des Repositorys.
- Der Release mit Daueraufträgen ist unter
  `~/Applications/FinanzVerwalter.app` installiert und ad hoc
  signaturgeprüft. Die Produktivdatei meldet Schema 14, 97 Konten,
  2.170 Buchungen, 0 Daueraufträge und Integrität `ok`. Das vorherige
  Bundle liegt ignoriert unter
  `build/FinanzVerwalter-vor-dauerauftraegen-20260731-0907.app`.
- Der Dauerauftrags-/Teststand wurde als Text im Telegram-Projektthread 894
  veröffentlicht. Computer Use bestätigte erneut den gesperrten Mac und
  konnte ihn erwartungsgemäß nicht automatisch entsperren; deshalb wurde
  keine angebliche App-Aufnahme versendet. Der echte Screenshot bleibt bis
  zum manuellen Entsperren offen.
- Das Kontoblatt besitzt nun geordnete, dauerhaft gespeicherte Kontotabs
  mit Kontoname, aktuellem Saldo, Wechsel, Schließen und Menü zum Öffnen
  weiterer Konten. Doppelte IDs werden beim Codieren entfernt; nicht mehr
  vorhandene Konten werden beim Laden ignoriert. Beim Schließen des aktiven
  Tabs wird deterministisch der Nachbartab gewählt.
- Der bestehende Präferenztest prüft zusätzlich Reihenfolge,
  Deduplizierung, ungültige UUIDs und veraltete Konto-IDs der Tabs.
- `⌘F` setzt jetzt tatsächlich den Fokus auf die globale Suche. `⌘S`
  speichert den geöffneten Buchungsdialog, und `⌘⇧S` öffnet beziehungsweise
  aktiviert eine Splitbuchung. `⌘N` und `⌘R` bleiben für neue Buchung und
  Kontoabgleich verfügbar.
- Die vollständige Suite besteht weiterhin mit 34 regulären Tests. Der
  SHA-256-Wert der produktiven Schema-14-Finanzdatei war vor und nach dem
  Lauf erneut identisch.
- Der optimierte Release mit Kontoblatt-Tabs und Tastaturkorrekturen ist
  unter `~/Applications/FinanzVerwalter.app` installiert und ad hoc
  signaturgeprüft. Schema 14, 97 Konten, 2.170 Buchungen und Integrität
  `ok` blieben unverändert. Das vorherige App-Bundle liegt ignoriert unter
  `build/FinanzVerwalter-vor-kontoblatt-tabs-20260731-0919.app`.
- Die vorhandene Saldo-Spalte wird nun per einmaliger Präferenzmigration auch
  für Nutzer eingeblendet, deren ältere gespeicherte Spaltenliste den später
  ergänzten Wert noch nicht kannte. Jede Buchungszeile zeigt weiterhin den
  kontenweisen laufenden Saldo; danach kann die Spalte bewusst wieder
  ausgeblendet werden.
- Das Kontoblatt erzeugt aus einem unveränderlichen Ausgabesnapshot ein
  mehrseitiges A4-Querformat-PDF mit exakt den sichtbaren Spalten,
  Filterbeschreibung, wiederholtem Tabellenkopf und `Seite x von y`. Das
  Menü `Ausgabe` öffnet wahlweise den nativen macOS-Druckdialog oder den
  PDF-Speicherdialog.
- `F3` übernimmt aus genau einer markierten Buchung das im Kontenblatt
  gewählte Feld als Filter. Unterstützt sind Empfänger, Verwendungszweck,
  vollständige Kategorie, Konto und Status; leere Felder oder eine
  mehrdeutige Auswahl liefern sichtbares Feedback.
- Zwei neue Tests prüfen F3-Feldabbildung sowie ein mehrseitiges Kontoblatt-
  PDF semantisch mit PDFKit. Der Präferenztest deckt zusätzlich die
  Saldo-Migration ab. Die vollständige Suite besteht damit aus 36 regulären
  Tests; der SHA-256-Wert der Produktivdatei war vor und nach dem Lauf
  bytegenau identisch.
- Der optimierte Release wurde unter
  `~/Applications/FinanzVerwalter.app` installiert und ad hoc
  signaturgeprüft. Die produktive Datei meldet weiterhin Schema 14,
  Integrität `ok`, 97 Konten, 2.170 Buchungen und 0 Daueraufträge. Das
  vorherige Bundle liegt ignoriert unter
  `build/FinanzVerwalter-vor-saldo-druck-f3-20260731-0929.app`.
- Der Kontoblatt-/Saldo-Stand wurde im Telegram-Projektthread 894 als
  Nachricht 937 veröffentlicht. Computer Use lief beim Zugriff auf das
  installierte App-Fenster erneut in einen Timeout, weil der Mac weiterhin
  gesperrt ist. Deshalb wurde kein fingierter Screenshot versendet und die
  echte visuelle Abnahme bleibt ausdrücklich offen.
- Da weder Homebrew noch `gh` vorhanden waren, wurde GitHub CLI 2.94.0 aus
  dem offiziellen arm64-Release geladen, gegen die veröffentlichte
  SHA-256-Prüfsumme geprüft und benutzerlokal unter `~/.local/bin/gh`
  installiert. Der Pfad ist in `~/.zshrc` ergänzt; `gh auth status`
  bestätigt das bestehende Keyring-Konto `pixelpuxel`.
- Commit `353118c` wurde auf `agent/qif-mehrkontenimport` gepusht. Der
  bestehende Draft-PR 1 zeigt auf diesen Commit und seine Beschreibung
  enthält Saldo-Migration, Kontoblatt-Druck/PDF, F3 und den aktualisierten
  Teststand.
- Migration 15 ersetzt den pauschalen Kontoabgleich durch Abgleichssätze mit
  Anfangssaldo, markierter Summe, optionaler Ausgleichsbuchung und
  unveränderlichen Einzelpositionen samt vorherigem Buchungsstatus.
  Migration 16 ergänzt eine monotone Folge, damit der jüngste Abgleich selbst
  bei identischem Datum und Zeitstempel eindeutig bleibt.
- Im neuen Abgleichsdialog werden gebuchte und bestätigte Kandidaten bis zum
  Auszugsdatum einzeln markiert. Anfangssaldo, markierte Summe, berechneter
  Saldo, Auszugsendsaldo und Differenz sind gleichzeitig sichtbar. Eine
  Differenz sperrt den Abschluss oder benötigt eine ausdrückliche zweite
  Bestätigung für eine Buchung mit Referenz `ABGLEICH`.
- Nur der jüngste aktive Abgleich kann zurückgenommen werden. Normale
  Buchungen erhalten ihren vorherigen Status; eine Differenzbuchung wird
  storniert statt gelöscht. Ältere Abgleiche bleiben lesbar und gegen
  Rücknahme gesperrt. Alle Schritte laufen atomar und erzeugen
  Auditereignisse.
- Der neue Domänentest deckt Teilmengen, Stichtag, Folge-Anfangssaldo,
  Differenzablehnung, explizite Ausgleichsbuchung, Schutz, eindeutige
  Rücknahmereihenfolge und Statuswiederherstellung ab. Ein separater
  Migrationstest übernimmt eine Schema-14-Abgleichshistorie nach Schema 16,
  ohne alte Einträge fälschlich rücknehmbar zu machen.
- Die vollständige XCTest-Abnahme über `xcodebuild test` besteht mit
  38 regulären Tests sowie einem bewusst übersprungenen
  opt-in-Real-QIF-Test.
- Vor der produktiven Migration wurde ausschließlich lokal die validierte
  Datei `Vor Migration 16 Kontoabgleich.qbackup` angelegt: Schema 14,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Abgleiche, SHA-256
  `605bc02a21f6666bcb22f23d5803397f78e72d05c09eb1db68068ae64bf1d422`.
- Der Release mit Kontoabgleich ist unter
  `~/Applications/FinanzVerwalter.app` installiert, ad hoc signaturgeprüft
  und gestartet. Die produktive Datei wurde additiv auf Schema 16 migriert
  und meldet Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Abgleiche und
  0 Abgleichspositionen. Das vorherige Bundle liegt ignoriert unter
  `build/FinanzVerwalter-vor-kontoabgleich-20260731-0951.app`.
- Commit `50668af` wurde auf `agent/qif-mehrkontenimport` gepusht und der
  bestehende Draft-PR 1 auf diesen Kontoabgleichs- und Teststand
  aktualisiert.
- Der geprüfte Textstatus wurde als Nachricht 938 im
  Telegram-Projektthread 894 veröffentlicht. Computer Use meldet weiterhin
  den gesperrten Mac; deshalb wurde ausdrücklich kein angeblicher
  App-Screenshot versendet. Die echte visuelle Abnahme bleibt bis zum
  manuellen Entsperren offen.
- Die zehn Kontoblattbefehle sind nun unter Einstellungen vollständig
  sichtbar und hinsichtlich Taste sowie Command, Shift, Option und Control
  anpassbar. Versionierter JSON-Codec, Standardrückfall, Deduplizierung,
  Konfliktanzeige und Schutz vor nackten Buchstaben-/Zifferntasten
  verhindern unbedienbare Konfigurationen.
- Löschen, Eingabe und Esc werden kontextabhängig ausgewertet. Entfernen
  bleibt bei aktiver Texteingabe dem Feldeditor vorbehalten. Außerhalb
  davon öffnet Löschen eine Bestätigung; die gesamte Auswahl und beide
  Umbuchungsseiten werden vorab geprüft und atomar gelöscht. Eine
  abgeglichene Buchung sperrt den gesamten Vorgang.
- Migration 17 ergänzt dateigebundene Buchungsvorlagen. `Als Vorlage
  merken` übernimmt Betrag, Konto, Empfänger, Kategorie, Status, Memo,
  Tags und Splits, normalisiert `Abgeglichen` zu `Gebucht` und entfernt
  Datum, Beleg- und Importidentität. Einzelne Umbuchungsseiten werden als
  irreführende Vorlage abgelehnt. Jede Anwendung erzeugt neue IDs und einen
  neuen Entwurf.
- Drei neue Tests prüfen Shortcut-Roundtrip, Konflikte und sichere
  Tastenbelegungen, den vollständigen Buchungsvorlagen-Roundtrip samt
  Splits sowie den atomaren Löschschutz. Die vollständige Suite besteht
  damit aus 42 regulären Tests und einem erwartungsgemäß übersprungenen
  opt-in-Real-QIF-Test.
- Vor der produktiven Migration wurde ausschließlich lokal die validierte
  Datei `Vor Migration 17 Shortcuts und Buchungsvorlagen.qbackup`
  angelegt: Schema 16, Integrität `ok`, 97 Konten, 2.170 Buchungen,
  0 Abgleiche und SHA-256
  `fce2cee4f6773ca17429823ba53d98b25235db5e53e8fbfc1a53aa812b4001da`.
- Der finale Release ist unter `~/Applications/FinanzVerwalter.app`
  installiert, ad hoc signaturgeprüft und gestartet. Die Produktivdatei
  meldet nach der additiven Migration Schema 17, Integrität `ok`,
  97 Konten, 2.170 Buchungen und 0 Buchungsvorlagen. Das vorherige
  App-Bundle liegt ignoriert unter
  `build/FinanzVerwalter-vor-shortcuts-vorlagen-20260731-1011.app`.
- Computer Use konnte den installierten Schema-17-Release nicht sichtbar
  aufnehmen, weil der Mac weiterhin gesperrt ist. Deshalb bleibt die
  visuelle Shortcut-/Vorlagenabnahme offen und es wird kein angeblicher
  Screenshot veröffentlicht.
- Die Funktionscommits `55c0c82` und `8f01061` wurden auf
  `agent/qif-mehrkontenimport` gepusht; Draft-PR 1 zeigt auf den zweiten
  Commit und dokumentiert 42 reguläre Tests. Telegram-Nachricht 939 im
  Projektthread 894 wurde auf denselben geprüften Stand aktualisiert.
- Migration 18 ergänzt frei definierbare, dateigebundene
  Mehrwertsteuerschlüssel. 0 %, 7 % und 19 % sind eigenständige
  Standarddatensätze; ein weiterer benutzerdefinierter 0-%-Schlüssel bleibt
  anhand seiner UUID unterscheidbar und wird nicht auf den Standard
  umgebogen.
- Kategorien speichern nun Beschreibung, Budgetierbarkeit,
  Standard-MwSt.-Schlüssel, deutsche Steuerzuordnung und optionale
  US-Steuerzeile. Der Kategorieneditor und die Detailansicht machen diese
  Felder vollständig sichtbar.
- Normale Buchungen berechnen aus dem Bruttobetrag wahlweise automatisch oder
  anhand eines manuellen Steuerbetrags Netto und Steuer. Jede Splitzeile kann
  einen eigenen Schlüssel und Modus besitzen. Gerundet wird mit `Decimal`
  kaufmännisch je Zeile; Beleg-Netto und Beleg-Steuer sind die Summe der
  bereits gerundeten Zeilen. Buchungsvorlagen übernehmen diese Felder.
- In der zweizeiligen Kontenblattansicht erscheinen für steuerbehaftete
  Buchungen zusätzlich MwSt.-Satz, Netto und Steuer. Die laufende
  Saldo-Spalte wird mit einer neuen einmaligen Präferenzmigration nicht nur
  in der aktuellen Spaltenauswahl, sondern auch in älteren benannten
  Kontenblattansichten sichtbar gemacht.
- Zwei Mehrwertsteuertests prüfen Zeilen-/Belegrundung, manuelle Validierung,
  Kategoriezuordnung, einen eigenständigen 0-%-Schlüssel und einen gemischten
  Split-Roundtrip. Der bestehende Saldo-Test prüft getrennte Konten,
  Eröffnungssalden und stornierte Buchungen; der Präferenztest prüft nun auch
  alte benannte Ansichten. Die vollständige direkte XCTest-Abnahme führte
  45 Tests aus: 44 bestanden, ein opt-in-Real-QIF-Test wurde erwartungsgemäß
  übersprungen, 0 Fehler.
- Vor Migration 18 wurde ausschließlich lokal die Sicherung
  `Vor Migration 18 Mehrwertsteuer.qbackup` angelegt und geprüft: Schema 17,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Buchungsvorlagen, SHA-256
  `6a3e519791081de0e70e81510a683f219a8a328658106eda44a69374b0577ef0`.
- Der Release ist unter `~/Applications/FinanzVerwalter.app` installiert,
  ad hoc signaturgeprüft und gestartet. Die produktive Datei meldet Schema 18,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, drei MwSt.-Schlüssel,
  0 Buchungsvorlagen und keine steuerlich veränderte Altbuchung. Das vorige
  Bundle liegt ignoriert unter
  `build/FinanzVerwalter-vor-mehrwertsteuer-20260731-1038.app`.
- Computer Use meldet den Mac weiterhin als gesperrt. Eine echte sichtbare
  Abnahme und ein neuer Screenshot sind deshalb noch offen; es wurde kein
  angeblicher Screenshot erzeugt.
- Der Funktionsstand ist als Commit `8c14296` auf
  `agent/qif-mehrkontenimport` gepusht; Draft-PR 1 dokumentiert Schema 18 und
  44 reguläre Tests. Telegram-Nachricht 940 im Projektthread 894 enthält den
  gleichen Prüfstand und weist ausdrücklich auf den fehlenden Screenshot
  wegen der macOS-Sperre hin.
- Migration 19 ergänzt Buchungen um Herkunft, externen Provider,
  externe Transaktions-ID, Gegenkonto-IBAN, End-to-End-ID,
  Mandatsreferenz, starken Dublettenfingerabdruck und optionalen Banksaldo
  nach der Buchung. Ein partieller eindeutiger Index schützt die Kombination
  aus Konto, Provider und nicht leerer externer Transaktions-ID.
- CSV-/TSV-, Einzel-QIF- und Mehrkonten-QIF-Vorschauen führen nun einen
  gestuften, deterministischen Abgleich gegen vorhandene Buchungen desselben
  Kontos aus. Betrag/Währung sind zwingend, das Datumsfenster ist zwischen
  0 und 14 Tagen einstellbar; Referenzen, IBAN, Empfänger und Zweck bilden
  den Score. Nur ein eindeutiger Treffer ab 90 Punkten wird vorgeschlagen.
  Gleichstände und weiche Kandidaten werden nie still zusammengeführt.
- Jede Vorschauzeile bietet `Neu importieren`, `Überspringen` oder einen
  konkreten vorhandenen Umsatz mit Empfänger, Datum, Betrag und Score. Das
  benutzte Datumsfenster gehört unveränderlich zur Vorschau und wird beim
  Commit gegen den aktuellen Datenbestand erneut angewandt. Eine vorhandene
  harte Bank-ID kann auch durch eine erzwungene Auswahl nicht dupliziert
  werden.
- Beim bestätigten Match bleiben lokale Kategorie, Memo, Splits, Tags,
  Mehrwertsteuer und Transferstruktur erhalten; Bankmetadaten werden
  ergänzt und erwartete/vorgemerkte Umsätze können zu gebuchten Umsätzen
  werden. Abgeglichene Buchungen behalten ihre geschützten Fachfelder.
- Zwei neue Tests prüfen Scoring, Mehrdeutigkeits- und Datumsfensterschutz
  sowie den atomaren CSV-Merge mit erhaltener lokaler Anreicherung und
  verbotener Bank-ID-Dublette. Die vollständige direkte XCTest-Abnahme
  führte 47 Tests aus: 46 bestanden, ein opt-in-Real-QIF-Test wurde
  erwartungsgemäß übersprungen, 0 Fehler.
- Vor Migration 19 wurde ausschließlich lokal die validierte Sicherung
  `Vor Migration 19 Import-Matching.qbackup` angelegt: Schema 18,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, drei MwSt.-Schlüssel,
  0 Buchungsvorlagen, SHA-256
  `b10e46a202099ac5130c4ad4e25f2c5412cee099d1bef455a10003594b09eca3`.
- Der finale Release-Build ist unter
  `~/Applications/FinanzVerwalter.app` installiert, ad hoc
  signaturgeprüft und gestartet. Die produktive Datei meldet Schema 19,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, drei MwSt.-Schlüssel und
  keine unbeabsichtigt gesetzte externe Identität in Altdaten. Der
  Schema-18-Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-import-matching-20260731-1057.app`.
- Computer Use meldet auch beim finalen Schema-19-Release den gesperrten
  Mac. Deshalb bleibt die visuelle Importdialog-Abnahme offen und es wird
  ausdrücklich kein angeblicher Screenshot veröffentlicht.
- Der Funktionsstand ist als Commit `f8200c6` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 zeigt auf genau diesen
  Commit und dokumentiert Schema 19 sowie 47 ausgeführte Tests.
- GitHub CLI 2.97.0 wurde aus dem offiziellen macOS-arm64-Release nach
  erfolgreicher SHA-256-Prüfung benutzerlokal unter `~/.local/bin/gh`
  installiert. Die vorhandene Schlüsselbund-Anmeldung für `pixelpuxel`
  funktioniert; keine Zugangsdaten wurden in Projektdateien geschrieben.
- Telegram-Nachricht 941 wurde im Projektthread 894 veröffentlicht. Sie
  enthält den geprüften Matching-, Release- und Teststatus sowie den
  ausdrücklichen Hinweis, dass wegen des gesperrten Macs noch kein echter
  Screenshot vorliegt.
- Migration 20 erweitert Regeln um deterministisch codierte, versionierte
  und rekursive UND-/ODER-Ausdrücke. 16 fachliche Bedingungsfelder und acht
  Operatoren decken unter anderem Konto, Empfänger/Auftraggeber, Zweck,
  Betrag/Vorzeichen, IBAN, BIC, Buchungstext, Referenzen, Zeitraum, Status
  und Herkunft ab. BIC, Gläubiger-ID und Buchungstext sind deshalb nun auch
  persistente Buchungsfelder und werden beim CSV-Import übernommen.
- Regelaktionen können Kategorie, Empfänger, Notiz, Tags und Zwecktext
  ändern, Zweck in die Notiz kopieren oder einen centgenauen Einzeilen-Split
  erzeugen. Widersprüchliche Mehrfachaktionen, ungültige Regex-Ausdrücke und
  fehlerhafte Centbereiche werden vor dem Speichern abgelehnt. Abgeglichene,
  stornierte und Transferbuchungen bleiben geschützt.
- Die Regeloberfläche zeigt Prioritätsreihenfolge und Konfliktmarken. Eine
  Trockenlauf-Tabelle stellt pro Treffer alle Vorher-/Nachher-Werte
  gegenüber; nur ausdrücklich ausgewählte Buchungen werden atomar
  angewandt. Eine einfach kategorisierte Kontoblattbuchung kann eine
  kontospezifische, noch nicht angewandte Regel erzeugen.
- Jede Anwendung schreibt in derselben SQLite-Transaktion ein vollständiges
  Undo-Paket mit Vorher-Snapshot und Nachher-Fingerabdruck. Die Rücknahme ist
  einmalig und vollständig. Wurde nur eine Buchung zwischenzeitlich
  bearbeitet oder gelöscht, wird das gesamte Undo ohne Teiländerung
  abgebrochen.
- Der neue Regeltest prüft verschachteltes UND/ODER, Regex-Validierung,
  Feldroundtrip, Konflikte, Vorher/Nachher-Vorschau, selektive Anwendung,
  Split-Erzeugung, vollständige Rücknahme und den atomaren Schutz nach
  manueller Nachbearbeitung. Die direkte Gesamtabnahme führte 48 Tests aus:
  47 bestanden, ein opt-in-Real-QIF-Test wurde erwartungsgemäß übersprungen,
  0 Fehler.
- Vor Migration 20 wurde ausschließlich lokal die validierte Sicherung
  `Vor Migration 20 Regel-Engine.qbackup` angelegt: Schema 19,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Regeln, SHA-256
  `8ad5b5fc1e4896b05355a5c317a461ccd6c173eadbf6e0c22cf6f80c106f9e28`.
- Der optimierte Release ist unter
  `~/Applications/FinanzVerwalter.app` installiert, ad hoc
  signaturgeprüft und gestartet. Die Produktivdatei meldet Schema 20,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Regeln, 0 Regelanwendungen
  und keine unbeabsichtigt gefüllten neuen Buchungsfelder. Der Vorgänger
  liegt ignoriert unter
  `build/FinanzVerwalter-vor-regel-engine-20260731-1124.app`.
- Computer Use meldet auch für die installierte Regeloberfläche den
  gesperrten Mac. Die sichtbare Abnahme und ein echter Screenshot bleiben
  bis zum manuellen Entsperren offen.
- Der Regel-/Undo-Stand ist als Commit `e13058a` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 zeigt auf genau diesen
  Commit und dokumentiert Schema 20 sowie 48 ausgeführte Tests.
- Telegram-Nachricht 942 wurde im Projektthread 894 veröffentlicht. Sie
  enthält den geprüften Regel-, Undo-, Release- und Teststatus und weist
  ausdrücklich auf den fehlenden Screenshot wegen der macOS-Sperre hin.
- Migration 21 ergänzt einen protokollunabhängigen, ausschließlich lesenden
  Banking-Adaptervertrag sowie dateigebundene Verbindungen,
  Kontenzuordnungen, Abrufläufe und schreibgeschützte Dauerauftrags-/
  Terminüberweisungsbestände. Adapter besitzen keinen Datenbankzugriff und
  rohe Antworten werden nicht gespeichert; protokolliert wird nur ihr
  SHA-256-Hash.
- Der aktivierbare lokale Simulator benötigt keine Bankzugänge und liefert
  deterministisch Konten, Salden, gebuchte und vorgemerkte Umsätze,
  Daueraufträge sowie Terminüberweisungen. FinTS/HBCI, PSD2/Open Banking und
  Web-Connectoren bleiben modelliert, aber in Oberfläche und Persistenz
  ausdrücklich deaktiviert. Depotbestand und Kurse werden vom Simulator
  nicht fälschlich als unterstützt gemeldet.
- Der Banking-Arbeitsbereich zeigt Verbindungen, die eindeutige Zuordnung
  externer zu lokalen Konten gleicher Währung, Vorgangsauswahl, Fortschritt,
  Abbruch, Bestände und Abrufhistorie. Die Vorschau zeigt jede Buchung,
  Status, konkrete Importentscheidung, angewandte Regeln, Regelkonflikte,
  Banksalden und Diagnose. Erst die Bestätigung schreibt Buchungen, Salden,
  Bestände und Abruflauf gemeinsam oder gar nicht.
- Neu abgerufene Umsätze durchlaufen vor dem Commit die konfliktgeschützte
  Regel-Pipeline und danach dasselbe gestufte Matching wie Dateiimporte.
  Stabile Provider-/Transaktions-IDs verhindern Dubletten; eine Wiederholung
  desselben Pakets erzeugt nur Skip-Entscheidungen und keine zweite Buchung.
- Zwei neue Tests prüfen deterministische Simulatorpakete, den Abbruch ohne
  Teilpaket, ehrliche Fähigkeiten, gesperrte Live-Provider, Zuordnung,
  Metadaten, Saldoübernahme, Bestände, Abrufhistorie, wiederholte Pakete,
  atomaren Fehlerabbruch und SQLite-Integrität. Die vollständige Abnahme
  führte 49 Tests aus: 48 bestanden, der opt-in-Test mit der privaten
  Real-QIF-Datei wurde erwartungsgemäß übersprungen, 0 Fehler. Debug-
  Test-Build und optimierter Release-Build bestehen.
- Vor Migration 21 wurde ausschließlich lokal die validierte Sicherung
  `Vor Migration 21 Banking-Abruf.qbackup` angelegt: Schema 20, Integrität
  `ok`, 97 Konten, 2.170 Buchungen, 0 Regeln, 0 Regelanwendungen, SHA-256
  `0c82c0f048127c39a4f8a3dda11b5ee4a85bb7796f9e4591f7b07b38fc2b848e`.
- Der optimierte Release ist unter `~/Applications/FinanzVerwalter.app`
  installiert, ad hoc signaturgeprüft und gestartet. Die Produktivdatei
  meldet Schema 21, Integrität `ok`, unverändert 97 Konten und 2.170
  Buchungen sowie erwartungsgemäß 0 Verbindungen, Zuordnungen, Abrufläufe
  und Bestände. Der Schema-20-Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-banking-20260731-1148.app`.
- Computer Use meldet den Mac weiterhin als gesperrt und konnte ihn nicht
  automatisch entsperren. Die sichtbare Banking-/Saldo-Abnahme und ein
  echter Screenshot bleiben deshalb offen; es wurde kein Ersatzbild als
  angeblicher App-Screenshot erzeugt.
- Der Banking-Stand ist als Commit `22575e6` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 zeigt auf diesen Commit,
  trägt nun den Titel „FinanzVerwalter: Kontoblatt, Regeln und sicherer
  Banking-Abruf“ und dokumentiert Schema 21 sowie 49 ausgeführte Tests.
- Telegram-Nachricht 943 wurde im Projektthread 894 veröffentlicht. Sie
  enthält den geprüften Saldo-, Banking-, Release-, GitHub- und Teststatus
  sowie den ausdrücklichen Hinweis auf den fehlenden Screenshot wegen der
  macOS-Sperre. Der dort dokumentierte Zielzählerstand beträgt 6.793.516
  verbrauchte Tokens.
- Das normale Kontenblatt besitzt nun einen persistent ein-/ausblendbaren
  rechten Minireport. Er folgt genau einer markierten Buchung und wertet
  wahlweise Empfänger, Kategorie oder Klasse/Tag aus. Text wird
  diakritika- und großschreibungsunabhängig verglichen, Stornos zählen nicht,
  Währungen bleiben getrennt und bei Splitbuchungen fließt nur der passende
  Splitbetrag in Einnahmen, Ausgaben und Saldo ein. Die letzten acht
  passenden Buchungen bleiben sichtbar.
- `Teilen` öffnet ein zweites Kontoblatt für ein anderes offenes Konto. Es
  besitzt eine eigene Kontowahl und unabhängige Status-, Kategorie- und
  Zeitraumfilter, übernimmt die globale Volltextsuche und zeigt Datum,
  Empfänger/Zweck, vollständigen Kategoriepfad, Betrag und kontenweisen
  laufenden Saldo. Doppelklick und Kontextmenü verwenden denselben
  Buchungseditor. Bei Primärkontowechsel oder gelöschtem Konto wird die
  Sekundärwahl deterministisch repariert.
- Minireport und Zwei-Konten-Ansicht schließen sich bei engem Desktoplayout
  gegenseitig aus. Sichtbarkeit und sekundäre Konto-ID liegen ausschließlich
  in lokalen Benutzereinstellungen und verändern die Finanzdatei nicht.
- Zwei neue reine Logiktests prüfen Minireport-Splitbeiträge,
  Stornoausschluss, Währungstrennung, diakritischen Empfängervergleich und
  die unabhängige Konto-/Status-/Kategorie-/Textfilterung des zweiten
  Kontenblatts. Die vollständige Abnahme führte 51 Tests aus: 50 bestanden,
  der opt-in-Test mit der privaten Real-QIF-Datei wurde erwartungsgemäß
  übersprungen, 0 Fehler. Test-Build und optimierter Release-Build bestehen.
- Der Release ist unter `~/Applications/FinanzVerwalter.app` installiert,
  ad hoc signaturgeprüft und gestartet. Die Produktivdatei blieb bei Schema
  21 mit Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Banking-Verbindungen
  und 0 Abrufläufen. Der Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-minireport-split-20260731-1202.app`.
- Computer Use meldet auch für diesen Release den gesperrten Mac. Eine
  sichtbare Minireport-/Zwei-Konten-/Saldo-Abnahme und ein echter Screenshot
  sind daher weiterhin offen und werden nicht als bestanden behauptet.
- Der Kontenblatt-Slice ist als Commit `13b36aa` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 zeigt auf diesen Commit
  und dokumentiert nun Minireport, geteilte Ansicht und 51 ausgeführte Tests.
- Telegram-Nachricht 944 wurde im Projektthread 894 veröffentlicht. Sie
  enthält denselben geprüften Kontenblatt-, Saldo-, Release-, GitHub- und
  Teststatus, bittet um manuelles Entsperren für die echte Sichtabnahme und
  nennt den Zielzählerstand von 6.898.694 verbrauchten Tokens.
