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
- Das Sammelkontoblatt kombiniert nun frei auswählbare offene Konten mit
  eigenen Status-, vollständigen Kategorie-, Zeitraum- und Volltextfiltern.
  Regelmäßige Vorgänge können deterministisch für 365 Tage eingeblendet
  werden; die erste Zukunftszeile erhält eine blaue Heute-Grenze.
- Reale und errechnete Zukunftszeilen erhalten einen kontenweisen laufenden
  Saldo ab Eröffnungssaldo. Stornos verändern ihn nicht. Kopf- und
  Statussummen bleiben nach Währung getrennt und schließen Umbuchungen und
  Stornos aus. Bei jeder Einschränkung steht ausdrücklich dabei, dass die
  gefilterte Bewegungssumme kein Kontostand ist.
- Mehrfachkategorisierung reicht ausschließlich persistente Buchungs-UUIDs
  an den bestehenden atomaren Commit weiter; errechnete Zukunftsvorgänge
  sind geschützt. Systemdruck und PDF übernehmen sichtbare Spalten, Zeilen,
  Zukunftsvorgänge und Filterbeschreibung.
- Benannte Sammelansichten speichern Kontenmenge, Status, Kategorie,
  Zeitraum, eigene Datumsgrenzen, Zukunftsschalter, Zeilenmodus und Spalten
  deterministisch als lokales JSON. Ungültige Konten werden beim Laden
  entfernt.
- Ein neuer Domänentest prüft Kontenkombination, kombinierte Filter,
  chronologische Reihenfolge, Währungstrennung, Stornoausschluss,
  Zukunftssalden und Ansichten-Roundtrip. Die vollständige Abnahme führte 52
  Tests aus: 51 bestanden, der private opt-in-Real-QIF-Test wurde
  erwartungsgemäß übersprungen, 0 Fehler. Test-Build und optimierter
  Release-Build bestehen.
- Der Release ist unter `~/Applications/FinanzVerwalter.app` installiert,
  ad hoc signaturgeprüft und gestartet. Schema 21, Integrität `ok`, 97
  Konten, 2.170 Buchungen, 0 Banking-Verbindungen und 0 Abrufläufe blieben
  unverändert. Der Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-sammelkontoblatt-20260731-1212.app`.
- Der Sammelkontoblatt-Stand ist als Commit `0430a89` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 zeigt auf diesen Commit
  und dokumentiert 52 ausgeführte Tests.
- Telegram-Nachricht 945 wurde im Projektthread 894 veröffentlicht. Sie
  enthält denselben geprüften Sammelkontoblatt-, Zukunfts-, Saldo-, Release-,
  GitHub- und Teststatus sowie den Zielzählerstand von 7.006.958 Tokens.
- Das Sammelkontoblatt kann nun persistent in Hauptansicht und
  `Sammelansicht B` geteilt werden. Ansicht B besitzt eine eigene persistente
  Kontenkombination, eigene Status-, Kategorie- und Zeitraumfilter sowie
  einen eigenen Zukunftsschalter. Beide Seiten verwenden denselben
  getesteten Query-/Saldoalgorithmus und kennzeichnen gefilterte Summen als
  Nicht-Kontostand.
- Direkte Berichtsaufrufe übergeben der Berichtswerkstatt exakt alle
  sichtbaren UUIDs einschließlich errechneter Zukunft oder den Empfänger,
  die Kategorie beziehungsweise Klasse/Tag einer markierten Buchung. Die
  Werkstatt zeigt und löst diese Direktauswahl sichtbar.
- Berichtsanfragen besitzen dafür drei rückwärtskompatible optionale Felder:
  UUID-Menge, exakter Empfänger und Zukunftsschalter. Empfänger werden
  diakritika- und großschreibungsunabhängig exakt verglichen. Nur direkte
  Zukunftsberichte ergänzen die bestehenden 365-Tage-Occurrences; normale
  Vorlagen bleiben unverändert.
- Der neue Test prüft exakte UUID-Selektion, diakritischen Empfängervergleich,
  Ausschluss anderer Empfänger, regelmäßige Zukunft und optionalen
  Query-Roundtrip. Die vollständige Abnahme führte 53 Tests aus: 52
  bestanden, der private opt-in-QIF-Test wurde erwartungsgemäß übersprungen,
  0 Fehler. Test-Build und optimierter Release-Build bestehen.
- Der Release ist unter `~/Applications/FinanzVerwalter.app` installiert,
  ad hoc signaturgeprüft und gestartet. Schema 21, Integrität `ok`, 97
  Konten, 2.170 Buchungen, eine vorhandene Berichtsvorlage und 0
  Banking-Verbindungen blieben erhalten. Der Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-direktberichte-20260731-1225.app`.
- Computer Use konnte auch diesen installierten Release nicht sichtbar
  prüfen: Die Fensterabfrage lieferte zunächst `cgWindowNotFound`, die
  anschließende App-Suche bestätigte den weiterhin gesperrten Mac. Deshalb
  bleibt ein echter Screenshot offen und wird nicht durch ein Ersatzbild
  vorgetäuscht.
- Der Direktbericht-/Zwei-Ansichten-Stand ist als Commit `4549569` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 zeigt auf diesen Commit
  und dokumentiert 53 ausgeführte Tests.
- Telegram-Nachricht 946 wurde im Projektthread 894 veröffentlicht. Sie
  enthält denselben geprüften Ansichten-, Bericht-, Zukunfts-, Saldo-,
  Release-, GitHub- und Teststatus sowie den Zielzählerstand von 7.107.447
  Tokens.

## 2026-07-31 – OFX/QFX über den sicheren Dateiimport

- FinanzVerwalter liest jetzt OFX-2-XML sowie klassische OFX-1/QFX-SGML-
  Kontoauszüge ohne neue Abhängigkeit. Bank- und Kreditkartenkonten,
  Währung, FITID, Buchungs-/Wertstellungsdatum, Betrag, Empfänger, Memo,
  Referenz und Buchungstext werden normalisiert.
- Mehrkontendateien erhalten eine explizite Zuordnung jedes externen Kontos
  zu einem vorhandenen lokalen Konto. Die Auswahl wird nach Währung
  eingeschränkt; eindeutige IBAN-/Kontonummerntreffer werden vorgeschlagen.
  Ohne vollständige Zuordnung bleibt die Vorschau gesperrt.
- Der Parser begrenzt Dateien auf 50 MB, Datensätze auf 200.000 und
  Freitextfelder. Beschädigte Buchungen und Währungsabweichungen werden
  einzeln sichtbar zurückgewiesen. Produktivdaten und Rohdateien gelangen
  weiterhin nicht in Git.
- OFX/QFX nutzt exakt das bestehende gestufte Matching, den SHA-256-
  Paketschutz und den atomaren SQLite-Commit. Dadurch bleiben lokale
  Anreicherungen bei einem bestätigten Match erhalten und derselbe Export
  kann nicht zweimal übernommen werden.
- Drei neue Tests decken Mehrkonten-XML einschließlich Kreditkarte und
  Valuta, SGML ohne schließende Blatt-Tags, Bankers-Rundung, beschädigte
  Zeilen, fehlende Zuordnung, Währungsabweichung, atomaren Commit,
  Paket-Idempotenz und SQLite-Integrität ab. Die vollständige Abnahme führte
  57 Tests aus: 56 bestanden, der private opt-in-Real-QIF-Test wurde
  erwartungsgemäß übersprungen, 0 Fehler. Debug-Build besteht.
- Der optimierte Release-Build besteht, ist ad hoc signiert und unter
  `~/Applications/FinanzVerwalter.app` installiert und gestartet. Der zuvor
  installierte Bundle-Stand liegt ignoriert unter
  `build/FinanzVerwalter-vor-ofx-qfx-20260731-1238.app`. Die Produktivdatei
  blieb bei Schema 21, Integrität `ok`, 97 Konten, 2.170 Buchungen, einer
  Berichtsvorlage und 0 Banking-Verbindungen. Ihr SHA-256 direkt vor der
  Installation war
  `0a8d6dd9695ccbace6155c05b82f9367c9621904bf9a68ef7bbb073f4d1bd77e`.
- Der exakte Zielzählerstand nach Release-Installation und Diffprüfung lag
  bei 7.334.872 verbrauchten Tokens.
- Der vollständige OFX/QFX-Stand wurde als Commit `825c3f3` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 nennt nun 57 ausgeführte
  Tests und die geprüfte Release-Installation.
- Telegram-Nachricht 947 wurde im Projektthread 894 (`/quicken`)
  veröffentlicht. Sie enthält den Import-, Test-, Release-, Datenbank- und
  GitHub-Status sowie den exakten Zielzählerstand von 7.383.816 Tokens. Ein
  neuer Screenshot bleibt wegen des gesperrten Macs ausdrücklich offen und
  wurde nicht durch ein Ersatzbild vorgetäuscht.

## 2026-07-31 – MT940 und camt.052/053/054

- Der bestehende Kontoauszugsimport liest nun zusätzlich MT940 aus `.sta`
  und `.mt940` sowie namespacebewusst camt.052, camt.053 und camt.054 aus
  `.xml`, `.c53` und `.c54`. Mehrere externe Konten werden weiterhin vor der
  Vorschau ausdrücklich vorhandenen lokalen Konten zugeordnet.
- MT940 verarbeitet mehrere `:20:`-Segmente, Konto/Währung, `:61:` mit
  getrenntem Buchungs- und Valutadatum einschließlich Jahreswechsel,
  Soll/Haben/Storno, Geschäftsvorfall, Kunden-/Bankreferenz sowie
  strukturierte `:86:`-Felder für Empfänger, Zweck, IBAN und BIC.
- camt verarbeitet `Stmt` und `Ntfctn`, Bankidentität, einzelne `Ntry` und
  aufgelöste Sammelbuchungen aus mehreren `TxDtls`. Valuta, Bank-,
  Transaktions-, End-to-End- und Mandatsreferenz, Empfänger, Gegenkonto,
  Buchungstext und Verwendungszweck bleiben in den normalisierten Buchungen
  erhalten.
- Beide Parser behalten die 50-MB-/200.000-Buchungsgrenze, SHA-256-
  Paketidentität, deterministische IDs, sichtbare Einzelablehnungen, das
  gestufte Matching und exakt den vorhandenen atomaren SQLite-Commitpfad.
  camt-Dateien mit DTD- oder ENTITY-Deklarationen werden vor dem Parser als
  Ganzes abgewiesen; externe Entitäten werden nicht aufgelöst.
- Drei neue Tests prüfen MT940-Mehrkonto-/`:86:`-Daten, camt-Batchdetails,
  Metadaten, atomaren SQLite-Commit, Paket-Idempotenz, Integrität,
  DTD-/ENTITY-Abweisung und eine separat fehlerhafte Buchung. Die frische
  vollständige Abnahme führte 60 Tests aus: 59 bestanden, der private
  opt-in-Real-QIF-Test wurde erwartungsgemäß übersprungen, 0 Fehler.
- Der optimierte Release-Build besteht, ist ad hoc signiert, unter
  `~/Applications/FinanzVerwalter.app` installiert und gestartet. Der zuvor
  installierte Bundle-Stand liegt ignoriert unter
  `build/FinanzVerwalter-vor-mt940-camt-20260731-1253.app`.
- Die Produktivdatei blieb vor und nach Installation bytegenau bei SHA-256
  `0a8d6dd9695ccbace6155c05b82f9367c9621904bf9a68ef7bbb073f4d1bd77e`,
  Schema 21, Integrität `ok`, 97 Konten, 2.170 Buchungen, einer
  Berichtsvorlage und 0 Banking-Verbindungen.
- Computer Use fand auch den installierten Release nicht sichtbar, weil der
  Mac weiterhin gesperrt ist und sich nicht automatisch entsperren lässt.
  Die echte UI-/Screenshot-Abnahme bleibt deshalb offen und wird nicht durch
  ein Ersatzbild vorgetäuscht.
- Der vollständige MT940-/camt-Stand wurde als Commit `a60b7c3` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 nennt nun 60 ausgeführte
  Tests, den XML-Schutz und die geprüfte Release-Installation.
- Der textliche Zwischenstand wurde im Telegram-Projektthread 894
  (`/quicken`) veröffentlicht. Er enthält Import-, Test-, Release-,
  Datenbank- und GitHub-Status sowie den exakten Zielzählerstand von
  7.606.790 Tokens; wegen des gesperrten Macs ausdrücklich keinen
  vorgetäuschten Screenshot.

## 2026-07-31 – Kontoblatt-Accessibility und Tastaturkontext

- Kontoauswahl, Status-/Kategorie-/Zeitraumfilter, Zeilenmodus, aktueller
  Saldo sowie Haupt-, zweites und Sammelkontoblatt besitzen jetzt stabile
  Accessibility-Identifier. Tabellen sprechen sichtbare und ausgewählte
  Buchungszahlen.
- Jede dynamische Kontoblattzelle liefert `Spaltentitel: Wert` als explizite
  Accessibility-Beschriftung. Damit bleiben insbesondere der vollständige
  Kategoriepfad und der laufende Saldo unabhängig von visueller Kürzung
  hörbar; echte Leerwerte werden als `Leer` benannt.
- Kontoblatt-Tabs kombinieren Auswahl und Schließen nicht länger zu einem
  untrennbaren AX-Element. Kontoauswahl mit Saldo/Auswahlstatus und die
  kontospezifische Schließen-Schaltfläche sind getrennt zugänglich.
- Der globale Kontextmonitor gibt Eingabe und Escape ohne geöffnetes Sheet
  wieder an Tabelle beziehungsweise AppKit zurück. Löschen wird während
  Texteingabe nicht abgefangen. Damit blockiert die konfigurierbare
  Dialogsteuerung nicht mehr die normale Tastaturnavigation.
- Zwei neue Tests prüfen vollständigen Kategorie-/Saldotext, Leerwerte,
  Singular/Plural und Auswahlstatus sowie die Kontextentscheidung für
  Eingabe, Escape und Löschen. Die frische vollständige Abnahme führte 62
  Tests aus: 61 bestanden, der private opt-in-Real-QIF-Test wurde
  erwartungsgemäß übersprungen, 0 Fehler.
- Der optimierte Release-Build besteht, ist ad hoc signiert, unter
  `~/Applications/FinanzVerwalter.app` installiert und gestartet. Der
  Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-ax-20260731-1303.app`.
- Die Produktivdatei blieb vor und nach Installation bytegenau bei SHA-256
  `0a8d6dd9695ccbace6155c05b82f9367c9621904bf9a68ef7bbb073f4d1bd77e`,
  Schema 21, Integrität `ok`, 97 Konten, 2.170 Buchungen, einer
  Berichtsvorlage und 0 Banking-Verbindungen.
- Die sichtbare VoiceOver-/Tastatur-/Screenshot-Abnahme bleibt wegen des
  nachweislich gesperrten Macs offen. Der neue statische AX-Test ersetzt
  diese Sichtprüfung ausdrücklich nicht.
- Der vollständige AX-/Tastaturstand wurde als Commit `9f59e9c` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 nennt nun 62 ausgeführte
  Tests und unterscheidet automatisierte Semantik von sichtbarer Abnahme.
- Der textliche Zwischenstand wurde im Telegram-Projektthread 894
  (`/quicken`) veröffentlicht. Er enthält denselben AX-, Tastatur-, Test-,
  Release-, Datenbank- und GitHub-Status sowie den exakten Zielzählerstand
  von 7.757.304 Tokens; wegen des gesperrten Macs ohne Screenshot.

## 2026-07-31 – Hierarchische Klassenfilter und atomare Organisation

- Haupt-, zweites und Sammelkontoblatt besitzen nun einen unabhängigen
  Filter für Klassen/Tags. Dabei werden Zuordnungen der Hauptbuchung und der
  Splitzeilen berücksichtigt. Einzel- und Sammelansichten speichern die
  gewählte Klasse rückwärtskompatibel; alte JSON-Ansichten ohne `tagID`
  bleiben lesbar.
- Klassen/Tags erscheinen in Kontenblättern, Editoren, Verwaltung,
  Regelaktionen und Berichtsfiltern mit dem vollständigen Pfad wie
  `Immobilie › Objekt A`. Die breite Hauptfilterleiste ist horizontal
  scrollbar und zerlegt dadurch das Kontenblatt bei kleineren Fenstern nicht.
- Die Mehrfachbearbeitung kann Kategorie und/oder die vollständige Menge der
  Tags auf Buchungsebene ersetzen. Der Store validiert vorab alle UUIDs,
  aktiven Ziele und Schutzregeln und schreibt die gesamte Auswahl atomar mit
  einer Versionsfortschreibung und Audit je Buchung. Abgeglichene Buchungen
  und Umbuchungen bleiben geschützt. Eine reine Tag-Änderung ist bei
  Splitbuchungen zulässig und verändert deren eigene Split-Tags nicht.
- Das Speichern einer Klassenhierarchie weist fehlende Eltern, Selbstbezüge
  sowie direkte und indirekte Kreise vor jeder Datenänderung ab.
- Der neue Domänentest prüft erfolgreiche Tag-Ersetzung, unveränderte
  Kategorien und Split-Tags sowie vollständigen Rollback bei einer
  abgeglichenen Buchung. Bestehende Tag- und Sammelkontoblatt-Tests prüfen
  zusätzlich Hierarchieschutz, exakten Tagfilter und alten JSON-Roundtrip.
  Die frische Gesamtabnahme führte 63 Tests aus: 62 bestanden, der private
  opt-in-Real-QIF-Test wurde erwartungsgemäß übersprungen, 0 Fehler.
- Debug- und optimierter Release-Build bestehen. Der Release ist ad hoc
  signiert, unter `~/Applications/FinanzVerwalter.app` installiert und als
  Prozess gestartet. Der Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-klassen-20260731-1315.app`.
- Die Produktivdatei blieb nach Installation bytegenau bei SHA-256
  `0a8d6dd9695ccbace6155c05b82f9367c9621904bf9a68ef7bbb073f4d1bd77e`,
  Schema 21, Integrität `ok`, 97 Konten, 2.170 Buchungen, einer
  Berichtsvorlage und 0 Banking-Verbindungen.
- Der exakte Zielzählerstand dieses geprüften Meilensteins beträgt
  7.984.886 Tokens.
- Die Implementierung wurde als Commit `74ad54e`, die Dokumentation als
  `d1bf030` auf `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 beschreibt
  nun die Klassenfilter, atomare Organisation und 63 ausgeführte Tests.
- Telegram-Nachricht 950 im Projektthread 894 (`/quicken`) enthält denselben
  Test-, Release-, Datenbank-, GitHub- und Tokenstatus. Ein Screenshot wurde
  nicht vorgetäuscht, weil `CGSSessionScreenIsLocked=Yes` den weiterhin
  gesperrten macOS-Anmeldebildschirm bestätigt.

## 2026-07-31 – Deterministisches Empfänger-SmartFill

- Der Buchungseditor bezeichnet die Empfängeraktenauswahl nun ausdrücklich
  als SmartFill und zeigt bei Treffern den passenden Alias sowie die Zahl
  bisheriger Verwendungen. Inaktive Empfängerakten werden ausgeschlossen.
- Suche und Sortierung sind aus der Oberfläche in den reinen
  `PayeeSmartFill`-Kern gezogen. Name und Aliase werden getrimmt sowie
  unabhängig von Großschreibung und Diakritika verglichen. Präfixtreffer
  stehen vor bloßen Teiltreffern; anschließend entscheiden Verwendung,
  normalisierter kanonischer Name und UUID deterministisch.
- Nur die ausdrückliche Picker-Auswahl übernimmt den kanonischen Namen und
  noch nicht belegte Kategorie-/Kontovorgaben. Verändert der Benutzer den
  Empfängertext danach manuell, wird die alte `payee_id` entfernt und damit
  keine falsche Aktenverknüpfung gespeichert.
- Ein neuer reiner Test prüft Aliaspräfix, kanonisches Präfix,
  Nutzungshäufigkeit, bloßen Teiltreffer, inaktive Akte und die Suche
  `cafe` gegen `Café`. Die frische Gesamtabnahme führte 64 Tests aus: 63
  bestanden, der private opt-in-Real-QIF-Test wurde erwartungsgemäß
  übersprungen, 0 Fehler.
- Debug- und optimierter Release-Build bestehen. Der Release ist ad hoc
  signiert, unter `~/Applications/FinanzVerwalter.app` installiert und als
  Prozess gestartet. Der Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-smartfill-20260731-1322.app`.
- Die Produktivdatei blieb bytegenau bei SHA-256
  `0a8d6dd9695ccbace6155c05b82f9367c9621904bf9a68ef7bbb073f4d1bd77e`,
  Schema 21, Integrität `ok`, 97 Konten, 2.170 Buchungen, einer
  Berichtsvorlage und 0 Banking-Verbindungen.
- Der exakte Zielzählerstand dieses geprüften SmartFill-Meilensteins beträgt
  8.085.000 Tokens.
- Implementierung `4595ff1` und Dokumentation `c26abb1` wurden auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 nennt nun SmartFill und 64
  ausgeführte Tests.
- Telegram-Nachricht 951 im Projektthread 894 (`/quicken`) enthält denselben
  SmartFill-, Test-, Release-, Datenbank-, GitHub- und Tokenstatus; wegen des
  gesperrten Bildschirms weiterhin ohne vorgetäuschten Screenshot.

## 2026-07-31 – SEPA-Empfängerakten und verlässliche Saldo-Spalte

- SQLite-Migration 22 ergänzt Empfängerakten um eine normalisierte und nach
  Mod 97 geprüfte SEPA-Gläubiger-ID. Standardklassen/-tags werden n:m in
  `payee_default_tags` gespeichert. `sepa_mandates` unterstützt mehrere
  eindeutige Mandatsreferenzen je Empfänger mit Unterschriftsdatum,
  OOFF/FRST/RCUR/FNAL-Sequenztyp, Notiz, Aktivstatus, Version und Audit.
- Die Empfängerverwaltung bearbeitet Gläubiger-ID, vollständige
  Standardklassenpfade und Mandate. SmartFill übernimmt neben Konto und
  Kategorie nun auch noch freie Standardklassen. Der Buchungseditor bietet
  aktive Mandate der gewählten Akte an und speichert Gläubiger-ID sowie
  Mandatsreferenz sowohl für einfache als auch für Splitbuchungen. Genau ein
  aktives Mandat wird vorgeschlagen; bei mehreren bleibt die Auswahl bewusst.
- Der laufende Buchungssaldo war bereits als dynamische Spalte, in beiden
  Kontenblättern, Sammelansicht, Accessibility und Druck/PDF implementiert.
  Der Präferenzmarker wurde auf V3 angehoben, damit auch eine
  Bestandsinstallation mit bereits gesetztem älteren Marker die Spalte
  zuverlässig einmalig in vorhandene Spaltenlisten und benannte Ansichten
  übernimmt. Danach bleibt sie frei ein- und ausblendbar.
- Die Schema-10- und Schema-14-Migrationsfixtures enthalten nun die in ihren
  historischen Versionen bereits vorhandenen Empfänger- und Tagtabellen. Die
  frische Gesamtabnahme führte 64 Tests aus: 63 bestanden, der private
  opt-in-Real-QIF-Test wurde erwartungsgemäß übersprungen, 0 Fehler. Debug-
  und optimierter Release-Build bestehen.
- Vor der Produktivmigration wurde die validierte Sicherung
  `Vor Migration 22 SEPA.qbackup` angelegt: Schema 21, Integrität `ok`, 97
  Konten, 2.170 Buchungen, SHA-256
  `ac49f035009a78f76751308e70aaad92520bc15178abaa0547f55d1dd9ba339e`.
- Der optimierte Release ist ad hoc signiert, unter
  `~/Applications/FinanzVerwalter.app` installiert und gestartet. Der
  Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-sepa-20260731-1342.app`.
- Die Produktivdatei ist nach kontrolliertem WAL-Checkpoint auf Schema 22,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, einer Berichtsvorlage, 0
  Banking-Verbindungen, 0 Mandaten und 0 Empfänger-Standardtagzuordnungen;
  SHA-256
  `2f03b155d3e06c81114252fd05d3cdaa9f44bff7450b13ca7ff70379d20c073a`.
- `CGSSessionScreenIsLocked=Yes` bestätigt weiterhin den gesperrten Mac.
  Deshalb wurde keine sichtbare UI-Abnahme oder ein Screenshot vorgetäuscht.
- Die Implementierung einschließlich Schema 22, Mandatsverwaltung,
  Buchungsverknüpfung und Saldo-Bestandsmigration wurde als Commit `c8cf402`
  auf `agent/qif-mehrkontenimport` festgeschrieben. Der exakte
  Zielzählerstand vor Dokumentationscommit und Veröffentlichung beträgt
  8.677.004 Tokens.
- Dokumentationscommit `ab04d25` wurde zusammen mit `c8cf402` auf GitHub
  gepusht; Draft-PR 1 trägt nun den SEPA-, Saldo-, Schema-22-, Release- und
  Teststatus. Telegram-Nachricht 952 im Projektthread 894 (`/quicken`)
  enthält denselben Zwischenstand und den exakten Zielzählerstand von
  8.690.206 Tokens, wegen des gesperrten Macs weiterhin ohne Screenshot.

## 2026-07-31 – Duplizieren, Kopieren und atomar Verschieben

- Das Kontoblatt besitzt im Kontextmenü einer einzelnen Buchung jetzt die
  eigenständigen Aktionen `Duplizieren …`, `Kopieren` und `In anderes Konto
  verschieben …`. Duplizieren verwendet den vorhandenen Vorlagenmechanismus
  für einen frischen Editorentwurf: neue Transaktions-/Split-IDs, heutiges
  Datum und gelöschte Referenz-, Transfer-, Import- und Bankidentitäten.
  Abgeglichene oder stornierte Quellen werden als gebucht vorbereitet;
  einzelne Umbuchungsseiten bleiben ausgeschlossen.
- `Kopieren` legt deutsches Datum, Empfänger, Verwendungszweck, vollständigen
  Kategoriepfad, Dezimalbetrag und ISO-Währung als stabile TSV-Zeile in die
  macOS-Zwischenablage. Eingebettete Tabulatoren werden neutralisiert.
- Der neue Verschieben-Dialog zeigt Quelle und Betrag und bietet nur weitere
  offene Konten derselben Währung an. Die Store-Operation liest und prüft
  Quelle und Ziel innerhalb einer einzigen SQLite-Transaktion, ändert nur
  `account_id` und Version und schreibt `move-account` in die Auditspur.
  Splitzeilen, Kategorien, Klassen/Tags, Steuer- und Bankmetadaten bleiben
  erhalten. Identisches, geschlossenes oder fremdwährungsgeführtes Ziel,
  abgeglichene Buchungen und einzelne Umbuchungsseiten werden abgewiesen.
- Der neue Integrationstest prüft atomare Saldenverschiebung, Erhalt beider
  Split-IDs und Bankmetadaten, sämtliche Negativfälle, Umbuchungs- und
  Abgleichschutz sowie SQLite-Integrität. Der bestehende Accessibility-Test
  prüft zusätzlich die exakte deutsche TSV-Ausgabe. Die Gesamtabnahme führte
  65 Tests aus: 64 bestanden, der private opt-in-Real-QIF-Test wurde
  erwartungsgemäß übersprungen, 0 Fehler. Debug- und optimierter Release-Build
  bestehen.
- Der optimierte arm64-Release ist ad hoc signiert, unter
  `~/Applications/FinanzVerwalter.app` installiert und als Prozess gestartet.
  Der Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-buchungsaktionen-20260731-1355.app`.
- Die Produktivdatei blieb nach Test, Installation und Start bytegenau
  unverändert: Schema 22, Integrität `ok`, 97 Konten, 2.170 Buchungen, eine
  Berichtsvorlage, 0 Banking-Verbindungen und SHA-256
  `2f03b155d3e06c81114252fd05d3cdaa9f44bff7450b13ca7ff70379d20c073a`.
- Die sichtbare Abnahme und ein neuer Screenshot werden nicht vorgetäuscht,
  solange die macOS-Sitzung gesperrt bleibt.
- Die geprüfte Implementierung ist als Commit `47fbca1` auf dem Branch
  `agent/qif-mehrkontenimport` festgeschrieben.
- Der exakte Zielzählerstand vor Dokumentationscommit und Veröffentlichung
  beträgt 8.872.972 Tokens.
- Die Commits `47fbca1` und `507b9a8` sind auf GitHub gepusht. Draft-PR 1
  trägt nun den Buchungsaktionen-, Saldo-, Sicherheits-, Release- und
  65-Test-Stand. Telegram-Nachricht 955 wurde erfolgreich im Projektthread
  894 (`/quicken`) veröffentlicht; sie enthält den verifizierten Stand und
  den Zielzählerstand von 8.883.736 Tokens, wegen der nachweislich gesperrten
  Sitzung bewusst ohne Screenshot.

## 2026-07-31 – Mehrere Empfänger-Bankverbindungen

- SQLite-Migration 23 ergänzt `payee_bank_accounts` mit Bezeichnung,
  Kontoinhaber, normalisierter und nach Mod 97 geprüfter IBAN, optionaler BIC,
  Bankname, Aktivstatus, Version und Audit. Ein partieller eindeutiger Index
  erzwingt höchstens eine Standardverbindung je Empfänger. Wird der Standard
  deaktiviert, wird eine andere aktive Verbindung deterministisch gewählt.
- Historische Bankdaten aus `payees.iban` und `payees.bic` werden bei der
  Migration als aktives `Standardkonto` übernommen. Der Empfängereditor zeigt
  beliebig viele Verbindungen und bearbeitet sie in einem eigenen Dialog.
- Der Zahlungseditor kann eine Empfängerakte und eine ihrer aktiven
  Bankverbindungen auswählen. Er übernimmt Kontoinhaber, IBAN und BIC sichtbar
  in den Entwurf. Der Store akzeptiert die optionale Verknüpfung nur, wenn
  Empfänger und Verbindung existieren, zusammengehören, aktiv sind und exakt
  dem normalisierten Bankdaten-Schnappschuss entsprechen. Historische und
  manuelle Zahlungsaufträge bleiben kompatibel; spätere Stammdatenänderungen
  verändern einen vorhandenen Auftrag nicht rückwirkend.
- Zwei neue Integrationstests prüfen Standardwechsel und -fallback,
  Normalisierung, inaktive/fremde/manipulierte Verbindungen, unveränderliche
  Zahlungsdaten, Schema-22-Übernahme und SQLite-Integrität. Die vollständige
  Suite führte 67 Tests aus: 66 bestanden, der private opt-in-Real-QIF-Test
  wurde erwartungsgemäß übersprungen, 0 Fehler. Debug- und optimierter
  Release-Build bestehen.
- Vor der Produktivmigration wurde
  `Vor Migration 23 Bankverbindungen.qbackup` erstellt und geprüft: Schema 22,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Empfänger und 0
  Zahlungsaufträge; SHA-256
  `4ddba0914490eaad97eaf44303748d9fd97ee519c0f7d92bdc3ed1091ea33e93`.
- Der optimierte arm64-Release ist ad hoc signiert, unter
  `~/Applications/FinanzVerwalter.app` installiert und gestartet. Der
  Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-bankverbindungen-20260731-1414.app`; der Stand
  vor der abschließenden Kontoinhaber-/Zuordnungshärtung zusätzlich unter
  `build/FinanzVerwalter-vor-bankverbindungen-haertung-20260731-1418.app`.
- Nach kontrolliertem WAL-Checkpoint meldet die Produktivdatei Schema 23,
  Integrität `ok`, 97 Konten, 2.170 Buchungen, eine Berichtsvorlage, 0
  Empfänger-Bankverbindungen, 0 Zahlungsaufträge und SHA-256
  `4d52e500499ac4508fc4e76a80591894f2337f98421fc84a8088e0c10194dbe1`.
- Die lokale Computersteuerung meldet weiterhin ausdrücklich, dass der Mac
  gesperrt ist und nicht automatisch entsperrt werden kann. Eine sichtbare
  UI-Abnahme und ein neuer Screenshot wurden deshalb nicht vorgetäuscht.
- Der exakte Zielzählerstand vor den Git-Commits beträgt 9.190.687 Tokens.
- Die geprüfte Implementierung einschließlich Migration 23, Empfänger- und
  Zahlungsoberfläche sowie der neuen Migrations-/Sicherheitstests ist als
  Commit `13153dc` festgeschrieben.
- Dokumentationscommit `c1b1e15` wurde zusammen mit `13153dc` auf GitHub
  gepusht. Draft-PR 1 trägt nun den Schema-23-, Empfänger-Bankverbindungs-,
  Sicherheits-, Release- und 67-Test-Stand.
- Telegram-Nachricht 962 wurde im Projektthread 894 (`/quicken`)
  veröffentlicht. Sie enthält denselben verifizierten Zwischenstand und den
  Zielzählerstand von 9.203.212 Tokens; wegen des gesperrten Macs bewusst
  ohne Screenshot.
- Der Zielzählerstand vor diesem Veröffentlichungsprotokoll beträgt
  9.207.144 Tokens.

## 2026-07-31 – SEPA-Core-Lastschriften und pain.008

- SQLite-Migration 24 ergänzt `direct_debit_orders`. Jeder Auftrag verknüpft
  ein offenes EUR-Gläubigerkonto, einen aktiven Empfänger, dessen aktive
  Bankverbindung und dessen aktives unterschriebenes Mandat. Gläubiger- und
  Schuldnerdaten, Mandatsreferenz/-datum/-sequenz, Fälligkeit, Betrag,
  Verwendungszweck und End-to-End-ID werden als unveränderlicher Schnappschuss
  gespeichert und innerhalb einer einzigen Transaktion gegen Manipulation
  geprüft.
- Der Zahlungsverkehr besitzt nun getrennte Bereiche für Überweisungen,
  Lastschriften und Daueraufträge. Der Lastschrifteditor wählt Konto,
  Zahlungspflichtigen, Bankverbindung und Mandat; die Detailansicht zeigt vor
  der simulierten Ausführung eine vollständige unveränderliche Zusammenfassung
  und verlangt eine doppelte Bestätigung. Freigabecodes werden nie gespeichert.
- Die bestehende sichere Statusmaschine wird wiederverwendet. Eine angenommene
  Lastschrift erzeugt atomar genau eine positive vorgemerkte Buchung mit
  Empfänger-, Bank-, Mandats-, Gläubiger- und End-to-End-Verknüpfung.
- `Pain008Exporter` schreibt deterministisch `pain.008.001.08` nach dem
  datierten Paket `EPC-SDD-CORE-2025-V1.1`, gültig ab 05.10.2025. Grundlage
  sind EPC SDD Core Rulebook 2025 V1.1 und C2PSP Implementation Guidelines
  2025 V1.0. CORE, Sequenztyp, Fälligkeit, Kontrollsummen, Gläubiger-ID,
  Mandat und Schuldnerdaten werden geschrieben; EUR-, Betrags-, BIC-, Längen-,
  Slash- und XML-Escaping-Regeln werden vor dem lokalen Export geprüft.
- Zwei neue Integrationstests prüfen Stammdatenzuordnung, Manipulationsschutz,
  unveränderte historische Mandatsdaten, Idempotenz, sämtliche zulässigen und
  unzulässigen Statusübergänge, genau-einmalige Buchung sowie deterministischen
  pain.008-Export und Negativfälle. Der temporäre Testdatenbank-Helfer schließt
  SQLite nun ausdrücklich vor dem Löschen und erzeugt keine API-Warnung mehr.
- Die vollständige Abnahme führte 69 Tests aus: 68 bestanden, der private
  opt-in-Real-QIF-Test wurde erwartungsgemäß übersprungen, 0 Fehler. Debug-
  und optimierter Release-Build bestehen.
- Derselbe opt-in-Test wurde anschließend separat mit einer nur temporär nach
  `/tmp` kopierten, SHA-256-identischen privaten 2025-QIF-Datei ausgeführt und
  bestand mit allen 97 Konten und 2.170 Buchungen. Die temporäre Kopie wurde
  danach entfernt; weder Pfad noch Inhalt werden eingecheckt.
- Vor der Produktivmigration wurde
  `Vor Migration 24 Lastschriften.qbackup` erstellt und geprüft: Schema 23,
  Integrität `ok`, 97 Konten und 2.170 Buchungen. Der optimierte Release wurde
  signaturgeprüft, unter `~/Applications/FinanzVerwalter.app` installiert und
  gestartet; der Vorgänger liegt ignoriert unter
  `build/FinanzVerwalter-vor-lastschriften-20260731-1445.app`.
- Nach kontrolliertem WAL-Checkpoint meldet die Produktivdatei Schema 24,
  Integrität `ok`, unverändert 97 Konten und 2.170 Buchungen, 0
  Lastschriftaufträge und SHA-256
  `ea205b382540a4eba259f5d57b0b32a39fbdbbdf614a2be6e0aa475a3b9b5345`.
- Die sichtbare UI-/VoiceOver-Abnahme und ein neuer Screenshot bleiben offen,
  solange die macOS-Sitzung gesperrt ist; dieser Nachweis wird nicht
  vorgetäuscht.
- Implementierung und Tests sind als Commit `98949c6`, die reproduzierbare
  Dokumentation als `7a73bde` auf
  `agent/qif-mehrkontenimport` festgeschrieben und auf GitHub gepusht.
  Draft-PR 1 dokumentiert Schema 24, SEPA-Core-Lastschrift, pain.008 und den
  69-Test-Stand.
- Telegram-Nachricht 968 wurde im Projektthread 894 (`/quicken`)
  veröffentlicht. Sie enthält den verifizierten Release-, Datenbank-, GitHub-
  und Teststand sowie den Zielzählerstand von 9.651.001 Tokens; wegen der
  gesperrten Sitzung bewusst ohne Screenshot.

## 2026-07-31 – Atomare Sammelüberweisungen und Sammellastschriften

- SQLite-Migration 25 ergänzt `payment_batches` und
  `payment_batch_items`. Ein Sammler speichert Art, Namen, gemeinsames Konto
  und Datum, Status, eindeutige Idempotenzkennung sowie die stabil geordnete
  Mitgliedschaft. Partielle Unique-Indizes verhindern, dass ein Einzelauftrag
  gleichzeitig mehreren Sammlern angehört.
- Sammelüberweisungen akzeptieren mindestens zwei freie Entwürfe mit offenem
  EUR-Konto, identischem Auftragstyp und Ausführungstag.
  Sammellastschriften verlangen zusätzlich identische Fälligkeit, Sequenz und
  Gläubigerschnappschüsse. Alle Prüfungen werden vor und innerhalb derselben
  Transaktion wiederholt; Beträge werden überlaufgeschützt in Minor-Units
  summiert.
- Die gesamte Gruppe durchläuft atomar die sichere Zustandsmaschine. Eine
  individuelle Statusänderung gebündelter Mitglieder wird im Store abgewiesen.
  Bei Annahme entstehen pro Überweisung genau eine negative und pro
  Lastschrift genau eine positive vorgemerkte Buchung mit der bestehenden
  stabilen Herkunftskennung. Teilzustände und Teilbuchungen sind damit
  ausgeschlossen.
- Der Zahlungsverkehr besitzt jetzt die vier Bereiche Überweisungen,
  Lastschriften, Sammler und Daueraufträge. Der Sammlereditor zeigt nur freie
  kompatible Entwürfe; die Detailansicht zeigt Art, Konto, Datum, Anzahl,
  Gesamtsumme, unveränderliche geordnete Positionen und Statuspfad. Vor der
  simulierten Ausführung sind Zusammenfassung und Ausführung doppelt zu
  bestätigen; Freigabecodes werden nicht gespeichert.
- `Pain001Exporter` und `Pain008Exporter` erzeugen für Sammler jeweils eine
  gemeinsame deterministische XML-Datei mit `BtchBookg=true`, Anzahl und
  Kontrollsumme auf Gruppen- und Zahlungsblockebene sowie genau einem
  Transaktionsblock pro Mitglied. Exakte Mitgliedschaft, Reihenfolge,
  gemeinsame Invarianten, Einzelwerte, XML-Escaping und bestehende datierte
  EPC-Regelpakete werden geprüft; der Export bleibt lokal und statusneutral.
- Zwei neue Integrationstests prüfen beide Sammlerarten vollständig:
  Persistenz, Deduplizierung, Schutz individueller Mitglieder, atomare
  Statusübergänge, genau-einmalige Buchungen, deterministischen Mehrpositions-
  pain.001-/pain.008-Export und Integrität. Die Migrationstests prüfen nun
  14→25 und 22→25.
- Der optimierte Release-Build besteht. Die vollständige Suite führte 71
  Tests aus: 70 bestanden, der private opt-in-Real-QIF-Test wurde ohne Pfad
  erwartungsgemäß übersprungen, 0 Fehler. Das Ergebnis liegt lokal unter
  `/tmp/FinanzVerwalter-FullTests-Schema25.xcresult`.
- Der private Test wurde anschließend separat mit einer SHA-256-identischen,
  nur temporär nach `/tmp` kopierten echten 2025-QIF-Datei ausgeführt und
  bestand in 1,000 Sekunden. Die temporäre Kopie wurde danach gelöscht; Datei,
  Inhalt und privater Quellpfad werden nicht versioniert.
- Vor der Produktivmigration wurde
  `Vor Migration 25 SEPA-Sammler.qbackup` erstellt und geprüft: Schema 24,
  Integrität `ok`, 97 Konten, 2.170 Buchungen und 0 Lastschriftaufträge.
- Der optimierte Release wurde signaturgeprüft, unter
  `~/Applications/FinanzVerwalter.app` installiert und gestartet. Der
  Vorgänger liegt reversibel und von Git ignoriert unter
  `build/FinanzVerwalter-vor-sepa-sammlern-20260731-1515.app`.
- Nach der Migration und kontrolliertem WAL-Checkpoint meldet die
  Produktivdatei Schema 25, Integrität `ok`, unverändert 97 Konten und 2.170
  Buchungen, 0 Lastschriftaufträge, 0 Sammler und 0 Sammlerpositionen sowie
  SHA-256
  `1ffa1d0f17dbd24cdc33863232ce5fbf482c6daf597ee2c51387e761719d518b`.
  Die installierte App wurde danach wieder gestartet.
- Implementierung und Tests sind als Commit `0b3f795` auf
  `agent/qif-mehrkontenimport` festgeschrieben; die reproduzierbare
  Dokumentation als Commit `5d0ffcc`. Beide Commits wurden auf GitHub
  gepusht. Draft-PR 1 dokumentiert Schema 25, atomare Sammelüberweisungen und
  Sammellastschriften, Mehrpositions-pain-Export sowie den 71-Test-Stand.
- Telegram-Nachricht 969 wurde im Projektthread 894 (`/quicken`)
  veröffentlicht. Sie enthält denselben verifizierten Release-, Datenbank-,
  GitHub- und Teststand sowie den Zielzählerstand von 9.973.156 Tokens. Wegen
  der gesperrten macOS-Sitzung wurde bewusst kein Screenshot vorgetäuscht.

## 2026-07-31 – Laufender Saldo und sichere pain.002-Statusberichte

- Das Kontenblatt besitzt weiterhin die dynamische Spalte `Saldo`. Sie zeigt
  pro Buchung den echten laufenden Kontostand aus Eröffnungssaldo und allen
  chronologisch vorhergehenden, nicht stornierten Buchungen des jeweiligen
  Kontos. Darstellung und Accessibility verwenden die Kontowährung und
  monospaced Ziffern; Ein- und Zweizeilenmodus ändern die Berechnung nicht.
- Die Einstellungenmigration wurde auf
  `registerVisibleColumnsIncludesBalanceV4` angehoben. Dadurch erhalten auch
  ältere lokale Spaltenkonfigurationen und gespeicherte Kontenblattansichten
  die Saldo-Spalte beim nächsten Start genau einmal. Danach bleibt sie über
  `Sichtbare Spalten` normal ein- und ausblendbar.
- SQLite-Migration 26 ergänzt unveränderliche
  `payment_status_reports` und `payment_status_report_items` samt
  Finanzdateibindung, SHA-256-Fingerabdruck, Originalreferenzen, Bankstatus und
  -gründen, lokaler Zielzuordnung sowie vorherigem und angewandtem Status.
- Der neue Parser akzeptiert ausschließlich höchstens 10 MB große
  `pain.002.001.10`-Dokumente im exakten ISO-Namespace und höchstens 20.000
  Positionen. DTD/ENTITY, externe Entitäten, falsche Namespaces und
  unvollständige Pflichtstruktur werden abgewiesen.
- Die Vorschau ordnet ausschließlich exakte, von den eigenen pain-Exporten
  erzeugte Nachrichten-, Zahlungsblock- und End-to-End-IDs zu. Nur `ACSC` und
  `RJCT` dürfen eingereichte oder unklare lokale Aufträge final annehmen oder
  ablehnen. Zwischenstände bleiben reine Historie und erzeugen keine
  Geldwirkung. Mitgliedszeilen eines Sammlers werden nicht einzeln angewandt.
- Direkt vor dem Commit wird die gesamte Zuordnung erneut gegen SQLite
  berechnet. Bericht, Positionen, Statuswechsel und genau-einmalige Buchungen
  werden in derselben äußeren Transaktion gespeichert; bestehende
  Store-Transaktionen verwenden dafür Savepoints. Einzel- und Sammelantworten
  sind damit atomar, veraltete Vorschauen und doppelte Fingerabdrücke werden
  abgewiesen.
- Der Zahlungsverkehr besitzt nun ein fünftes Segment `Statusberichte` mit
  sicherem XML-Dateiimport, positionsweiser Vorschau, zweiter Bestätigung,
  persistenter Berichtsliste und vollständiger Positionshistorie.
- Die vollständige Suite führte 75 Tests aus: 74 bestanden, der private
  opt-in-Real-QIF-Test wurde ohne Pfad erwartungsgemäß übersprungen, 0 Fehler.
  Das Ergebnis liegt unter
  `/tmp/FinanzVerwalter-FullTests-Schema26-Saldo.xcresult`. Saldo-/Ansichten-,
  Parserhärtungs-, Einzelstatus-, Sammlerstatus-, Migration- und
  Integritätstests sind enthalten.
- Der private echte 2025-QIF-Test wurde anschließend separat mit einer
  SHA-256-identischen temporären Kopie ausgeführt und bestand. Die Kopie wurde
  danach gelöscht; Quelldatei, privater Pfad und Inhalte bleiben außerhalb
  des Repositorys.
- Vor der Produktivmigration wurde
  `Vor Migration 26 pain.002-Status und Saldo.qbackup` erstellt und geprüft:
  Schema 25, Integrität `ok`, 97 Konten und 2.170 Buchungen. Der optimierte
  Release-Build bestand und wurde signaturgeprüft.
- Die bisherige App liegt reversibel und von Git ignoriert unter
  `build/FinanzVerwalter-vor-pain002-saldo-20260731-1542.app`. Der neue Release
  ist unter `~/Applications/FinanzVerwalter.app` installiert und gestartet.
- Nach kontrolliertem WAL-Checkpoint meldet die Produktivdatei Schema 26,
  Integrität `ok`, unverändert 97 Konten und 2.170 Buchungen sowie 0
  Statusberichte und 0 Statuspositionen. Ihr neuer stabiler SHA-256-Wert ist
  `fd7a49fd63d4cb45fdef487afaf6324de6b85f4a7a93a256d486492a3121441c`.
- Die Computersteuerung bestätigte erneut, dass die macOS-Sitzung gesperrt ist
  und nicht automatisch entsperrt werden kann. Eine sichtbare UI-/VoiceOver-
  Abnahme und ein echter neuer Screenshot bleiben deshalb offen und werden
  nicht vorgetäuscht.
- Implementierung und Tests sind als Commit `a19c53f`, die reproduzierbare
  Dokumentation als `4e6ae2b` auf `agent/qif-mehrkontenimport` festgeschrieben
  und nach GitHub gepusht. Draft-PR 1 enthält den Schema-26-, Saldo-, Test- und
  Produktionsstand.
- Telegram-Nachricht 970 wurde im Projektthread 894 (`/quicken`)
  veröffentlicht. Sie nennt Saldo-Migration, sicheren pain.002-Import,
  75-Test-Stand, private QIF-Prüfung, Produktivmigration, GitHub-Commits und
  Zielzählerstand von 10.372.101 Tokens. Wegen der gesperrten Sitzung wurde
  ausdrücklich kein Screenshot angehängt oder vorgetäuscht.

## 2026-07-31 – Sicherer pain.001-/pain.008-Auftragsimport

- `PainInstructionImporter` liest ausschließlich `pain.001.001.09` und
  `pain.008.001.08` in ihren exakten ISO-Namespaces. Eingaben sind auf 10 MB
  und 20.000 Positionen begrenzt; DTD/ENTITY und externe Entitäten werden
  abgewiesen. Erstellungszeit, IDs, SEPA-Servicelevel, EUR-Beträge,
  IBAN/BIC, Daten, CORE-Sequenz sowie Anzahl und Kontrollsumme auf Gruppen-
  und Zahlungsblockebene werden geprüft.
- Die Vorschau ordnet ein offenes EUR-Konto nur über exakten Inhabernamen,
  IBAN und gegebenenfalls BIC zu. Empfängerbankverbindungen benötigen aktive,
  exakt übereinstimmende Stammdaten. Lastschriften verlangen zusätzlich genau
  das aktive Mandat mit Referenz, Datum und Sequenz. Mehrdeutigkeit wird nicht
  geraten; eine Überweisung ohne Empfängerakte darf nur sichtbar unverbunden
  als Entwurf entstehen.
- Migration 27 ergänzt `payment_instruction_imports` und
  `payment_instruction_import_items`. Auswahl und zweite Bestätigung erzeugen
  ausschließlich Entwürfe, nie Versand, Statuswechsel oder Buchung. Alle
  Zuordnungen werden im Commit erneut geprüft. Ein vollständiger
  Mehrpositionsblock wird in Quellreihenfolge als Sammler rekonstruiert;
  Teilauswahlen bleiben Einzelentwürfe. Import, Historie und Audit sind eine
  atomare Transaktion und der Dateihash verhindert Doppelübernahmen.
- Der Zahlungsverkehr besitzt nun ein sechstes Segment `Dateiimporte` mit
  sicherem lokalen Dateidialog, unveränderlicher Positionsvorschau,
  Selektionsbegründungen, ausdrücklichem Entwurfshinweis sowie persistenter
  Import- und Positionshistorie.
- Vier neue Tests prüfen Export-Import-Rundläufe beider pain-Formate,
  DTD/ENTITY, falschen Namespace und manipulierte Kontrollsummen, atomaren
  idempotenten Überweisungs-/Sammlerimport sowie exakte und beim Commit erneut
  geprüfte Lastschriftmandate. Die Migrationstests decken Schema 14→27 und
  Schema 22→27 ab.
- Die vollständige Suite unter
  `/tmp/FinanzVerwalter-FullTests-Schema27-PainImport.xcresult` führte 79
  Tests aus: 78 bestanden, der private opt-in-Real-QIF-Test wurde ohne Pfad
  erwartungsgemäß übersprungen, 0 Fehler. Derselbe private echte
  2025-QIF-Test bestand anschließend mit einer ausschließlich temporären
  Kopie; sie wurde danach gelöscht und bleibt vollständig außerhalb von Git.
- Der optimierte Release-Build unter
  `build/DerivedData-Schema27-PainImport/Build/Products/Release` bestand. Vor
  der Produktivmigration wurde die App kontrolliert beendet und die geprüfte
  Sicherung `Vor Migration 27 pain-Auftragsimport.qbackup` angelegt: Schema
  26, Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Statusberichte und 0
  Statuspositionen. Die bisherige App liegt reversibel unter
  `build/FinanzVerwalter-vor-pain-import-20260731-1609.app`.
- Der neue Release ist ad hoc signiert, streng signaturgeprüft, unter
  `~/Applications/FinanzVerwalter.app` installiert und zweimal erfolgreich
  gestartet. Nach kontrolliertem WAL-Checkpoint meldet die Produktivdatei
  Schema 27, Integrität `ok`, unverändert 97 Konten und 2.170 Buchungen sowie
  0 Auftragsimporte und 0 Importpositionen. Ihr stabiler SHA-256-Wert ist
  `053ae13acef1ad8140500a7dec96e39114cbeb60b5fe00ecb5ecf6d37fc73849`.
- Die Computersteuerung bestätigt erneut eine gesperrte macOS-Sitzung, die
  sich nicht automatisch entsperren lässt. Die sichtbare UI-/VoiceOver-
  Abnahme und ein echter neuer Screenshot bleiben offen; es wurde nichts
  vorgetäuscht.
- Implementierung und Tests sind als Commit `ddebfbc`, die reproduzierbare
  Dokumentation als `26bfdd8` auf `agent/qif-mehrkontenimport` festgeschrieben
  und nach GitHub gepusht. Draft-PR 1 dokumentiert Schema 27, Sicherheit,
  Vollsuite, privaten QIF-Test und Produktionsmigration.
- Telegram-Nachricht 971 wurde im Projektthread 894 (`/quicken`)
  veröffentlicht. Sie enthält denselben Import-, Test-, Release-, Datenbank-
  und GitHub-Stand sowie den Zielzählerstand von 10.740.657 Tokens. Wegen der
  bestätigten Bildschirmsperre wurde ausdrücklich kein Screenshot angehängt
  oder vorgetäuscht.

## 2026-07-31 – EPC-QR-Rechnungsdaten und SEPA-Zweckcode

- Die offizielle EPC069-12-Spezifikation wurde in Version 3.1 vom 19.03.2024
  als verbindliches Rechnungsprofil gewählt. Das separate
  Point-of-Interaction-Verfahren ist ausdrücklich nicht behauptet.
- `EPCQRImporter` liest lokale Bilder offline über macOS Vision und verlangt
  genau einen QR-Code. Bilddateien sind auf 20 MB, Bildkanten auf 12.000 Pixel
  begrenzt. Der Parser akzeptiert ausschließlich BCD, Version 001/002,
  Zeichensatz 1–8 und SCT, rekonstruiert den deklarierten Zeichensatz und
  prüft die offizielle 331-Byte-Grenze.
- BIC, Empfängername, Mod-97-IBAN, optionaler EUR-Betrag zwischen 0,01 und
  999.999.999,99 Euro, Zweckcode, strukturierte Referenz oder alternativer
  Freitext und Empfängerhinweis werden längen- und strukturgeprüft. RF-
  Referenzen benötigen eine korrekte ISO-11649-Prüfsumme. Steuerzeichen,
  widersprüchliche Referenz-/Textbelegung und ein abschließender Feldtrenner
  werden abgewiesen.
- Der Scan füllt ausschließlich den vorhandenen sichtbaren
  Überweisungseditor. Er speichert, sendet und bucht nichts. Eine aktive
  Empfängerbank wird nur bei genau einer exakten Namens-/IBAN-/BIC-
  Übereinstimmung verknüpft. Die Bildanalyse läuft außerhalb des UI-Threads.
- Migration 28 ergänzt `payment_orders.purpose_code`. Der optionale
  vierstellige SEPA-Zweckcode ist Teil der Idempotenzkennung, bleibt im
  Auftragsdetail sichtbar, wird bei pain.001-Auftragsimporten erhalten und als
  optionales `Purp/Cd` in Einzel- und Sammler-pain.001 exportiert.
- Zwei neue Tests prüfen Parser und Negativfälle sowie einen tatsächlich im
  Test erzeugten PNG-QR-Code, Vision-Decodierung, Persistenz, pain.001-
  Rundlauf und Integrität. Die Migrationsfixtures decken Schema 14→28 und
  Schema 22→28 ab. Die vollständige Abnahme unter
  `/tmp/FinanzVerwalter-FullTests-Schema28-EPCQR.xcresult` führte 81 Tests
  aus: alle 81 einschließlich des lokalen privaten 2025-QIF-Akzeptanztests
  bestanden, 0 Fehler. Dessen nur temporäre Kopie wurde danach tatsächlich
  gelöscht und ihre Abwesenheit geprüft.
- Der optimierte Release-Build unter
  `build/DerivedData-Schema28-EPCQR/Build/Products/Release` bestand. Vor der
  Produktivmigration wurde die App geordnet beendet und die geprüfte
  Sicherung `Vor Migration 28 EPC-QR und Zweckcode.qbackup` angelegt: Schema
  27, Integrität `ok`, 97 Konten, 2.170 Buchungen sowie 0 Zahlungsaufträge,
  0 Auftragsimporte und 0 Importpositionen. Ihr SHA-256-Wert ist
  `d20ddb6ec34646df9135609d6c59644a6f824707e1c763bcb45935d629808f19`.
  Die bisherige App liegt reversibel unter
  `build/FinanzVerwalter-vor-epc-qr-20260731-163051.app`.
- Der neue Release ist ad hoc signiert, streng signaturgeprüft und unter
  `~/Applications/FinanzVerwalter.app` installiert. Nach Migration,
  kontrolliertem Beenden, WAL-Checkpoint und erneutem Start meldet die
  Produktivdatei Schema 28, Integrität `ok`, unverändert 97 Konten und 2.170
  Buchungen; die verpflichtende `purpose_code`-Spalte ist vorhanden. Ihr
  stabiler SHA-256-Wert ist
  `21785657cc4807d072410e5736d900727b1b5bb3b7c30b187424fc166d07226c`.
  Nach einer zusätzlichen Normalisierung des Zweckcodes im Sammlerexport
  bestand der gezielte QR-/Persistenz-/Export-Test erneut, der optimierte
  Release wurde erneut erfolgreich gebaut und kontrolliert installiert. Das
  davor installierte Schema-28-Bundle liegt unter
  `build/FinanzVerwalter-schema28-vor-exportnormalisierung-20260731-163435.app`.
  Der finale ausführbare Code hat SHA-256
  `4618e5cd9261b5e0c9e63296c8a04bbf47d0f51eed733d5c58b6f63d1a90dbc7`;
  die installierte App läuft nach dem finalen Neustart als Prozess 60289 und
  meldet weiterhin Schema 28, Integrität `ok`, 97 Konten und 2.170 Buchungen.
- Implementierung und Tests sind als Commit `f543d7b`, die reproduzierbare
  Dokumentation als `f3bbd88` auf `agent/qif-mehrkontenimport`
  festgeschrieben und nach GitHub gepusht. Draft-PR 1 nennt jetzt Schema 28,
  EPC-QR, Zweckcode, die vollständige Testabnahme und die Produktivmigration.
- Die Computersteuerung bestätigte unmittelbar vor der Statusmeldung erneut
  die gesperrte macOS-Sitzung; ein aktueller Screenshot war deshalb nicht
  möglich und wurde nicht vorgetäuscht. Telegram-Nachricht 972 wurde im
  Projektthread 894 (`/quicken`) veröffentlicht. Sie enthält den Schema-28-,
  Test-, Release-, Datenbank- und GitHub-Stand sowie den Zielzählerstand von
  11.074.428 Tokens und weist ausdrücklich auf den fehlenden Screenshot hin.

## 2026-07-31 – Versionierter TARGET-Bankarbeitstagskalender

- Als fachliche Primärquellen wurden das aktuelle Bundesbank-Merkblatt
  „Unbarer Zahlungsverkehr an Feiertagen“ und der T2-Betriebskalender der EZB
  verwendet. Beide nennen für Euro-TARGET neben Wochenenden den 1. Januar,
  Karfreitag, Ostermontag, 1. Mai sowie 25. und 26. Dezember. Die Bundesbank
  bestätigt zugleich SEPA-Echtzeitüberweisungen als 24/7-Verfahren.
- `BankingCalendarProfile` stellt `target-euro-v1` und das bisherige
  Montag-bis-Freitag-Verhalten als `weekdays-v1` bereit. Ostersonntag wird
  deterministisch nach dem gregorianischen Kalender berechnet; daraus folgen
  Karfreitag und Ostermontag. Eine Fälligkeit kann unverändert, vorwärts oder
  rückwärts auf einen Bankarbeitstag verschoben werden.
- Migration 29 ergänzt jede Dauerauftragsvorlage um die stabile
  Kalenderkennung und jede materialisierte oder übersprungene Historienzeile
  um Kennung und Version. Damit verändern künftige Regelpakete bestehende
  Historie nicht still. Editor, Detail und Historie zeigen Profil und Version.
- Überweisungs- und Lastschrifteditor warnen sichtbar bei TARGET-Schließtagen,
  lassen den lokalen Entwurf aber editierbar. Echtzeitüberweisungen zeigen die
  getrennte 24/7-Semantik. Es entsteht weiterhin weder Versand noch Buchung.
- Ein neuer Test prüft feste und bewegliche Schließtage 2026/2027,
  Osterwochenende in beide Richtungen, Weihnachten, Kompatibilitätsprofil und
  „nicht verschieben“. Der Dauerauftragstest prüft zusätzlich die persistente
  Kalenderkennung/-version. Die Migrationsfixtures decken Schema 14→29 und
  Schema 22→29 ab.
- Die vollständige isolierte Suite unter
  `/tmp/FinanzVerwalter-FullTests-Schema29-BankCalendar.xcresult` führte 82
  Tests aus: 81 bestanden, der private opt-in-Real-QIF-Test wurde ohne
  temporären Pfad erwartungsgemäß übersprungen, 0 Fehler. Der private echte
  2025-QIF-Test bestand anschließend separat mit einer ausschließlich
  temporären Kopie; sie wurde danach gelöscht und ihre Abwesenheit geprüft.
- Der optimierte Release-Build unter
  `build/DerivedData-Schema29-BankCalendar/Build/Products/Release` bestand.
  Vor der Produktivmigration wurde die App geordnet beendet und die geprüfte
  Sicherung `Vor Migration 29 TARGET-Bankkalender.qbackup` angelegt: Schema
  28, Integrität `ok`, 97 Konten, 2.170 Buchungen, 0 Daueraufträge und 0
  Ausführungshistorienzeilen. Ihr SHA-256-Wert ist
  `4506497ed2bd53b5171b1f7301e6871644be2a1a7746e49fd7bf58d64ed27e73`.
  Die bisherige App liegt reversibel unter
  `build/FinanzVerwalter-vor-bankkalender-20260731-165836.app`.
- Der neue Release ist ad hoc signiert, streng signaturgeprüft und unter
  `~/Applications/FinanzVerwalter.app` installiert. Sein ausführbarer Code
  hat SHA-256
  `8a91e52b4a808ae90310141e20c2b611a1177cf455d30e4c330fbbdcd0d216c7`.
  Nach Migration, kontrolliertem Beenden, WAL-Checkpoint und erneutem Start
  meldet die Produktivdatei Schema 29, Integrität `ok`, unverändert 97 Konten
  und 2.170 Buchungen; alle drei neuen Kalenderfelder sind verpflichtend
  vorhanden. Ihr stabiler SHA-256-Wert ist
  `a50877f038a9f4c18d119633dc7daa8f2464aad2369eb45df970e2a173d104f9`.
  Die installierte App läuft nach dem Neustart als Prozess 62072.
- Implementierung und Tests sind als Commit `1982ebc`, die reproduzierbare
  Dokumentation als `e66910c` auf `agent/qif-mehrkontenimport`
  festgeschrieben und nach GitHub gepusht. Draft-PR 1 dokumentiert jetzt
  Schema 29, TARGET-Kalender, 24/7-Ausnahme, Vollsuite, privaten QIF-Test und
  Produktivmigration.
- Die Computersteuerung bestätigte unmittelbar vor der Statusmeldung erneut
  die gesperrte macOS-Sitzung; ein aktueller Screenshot war deshalb nicht
  möglich und wurde nicht vorgetäuscht. Telegram-Nachricht 973 wurde im
  Projektthread 894 (`/quicken`) veröffentlicht. Sie enthält denselben
  Kalender-, Test-, Release-, Datenbank- und GitHub-Stand sowie den
  Zielzählerstand von 11.325.105 Tokens.

## 2026-07-31 – Direkter Systemdruck der Berichtswerkstatt

- Das vorhandene PDF-Menü der Berichtswerkstatt bietet zusätzlich
  `Drucken …`. Der Weg erzeugt über dieselbe Hilfsfunktion wie der PDF-Export
  exakt den aktuellen gefilterten `TransactionReportSnapshot`, dieselben
  Metadaten und dieselbe Hoch-/Querformatausrichtung und übergibt ihn erst
  nach dem Klick an den macOS-Systemdruckdialog.
- Der Druckpfad besitzt keine zweite Auswertungslogik und verändert keine
  Buchung oder Berichtsvorlage. Fehler werden über die vorhandene sichtbare
  Fehlermeldung der App gemeldet.
- Der gezielte mehrseitige PDF-Semantiktest
  `testReportPDFExportCreatesReadableMultipagePrintLayout` bestand nach der
  UI- und Datenstromänderung erneut. Der vollständige 82-Test-Lauf von Schema
  29 bleibt der unmittelbar vorausgehende Baseline-Nachweis.
- Der optimierte Release unter `build/DerivedData-ReportPrint` bestand, wurde
  ad hoc signiert, streng geprüft und kontrolliert installiert. Das vorherige
  Schema-29-Bundle liegt reversibel unter
  `build/FinanzVerwalter-vor-berichtsdruck-20260731-170553.app`. Der neue
  ausführbare Code hat SHA-256
  `546c04a0ebcc3be49998862737473d61a7b9b4b6ef54694b2ce85d859f370db4`.
  Die App läuft als Prozess 62576; die Produktivdatei blieb bytegleich bei
  SHA-256 `a50877f038a9f4c18d119633dc7daa8f2464aad2369eb45df970e2a173d104f9`
  und meldet Schema 29, Integrität `ok`, 97 Konten und 2.170 Buchungen.
- Implementierung und Dokumentation sind als Commits `0f316a9` und
  `4e7f1ae` gepusht; Draft-PR 1 enthält den direkten Systemdruck und seinen
  gezielten Nachtest. Telegram-Nachricht 974 wurde im Projektthread 894
  (`/quicken`) mit demselben Stand und dem Zielzählerstand 11.379.062 Tokens
  veröffentlicht. Wegen der weiterhin bestätigten Bildschirmsperre wurde
  kein Screenshot angehängt oder vorgetäuscht.

## 2026-07-31 – Zweite Gruppierungsdimension in Berichten

- Die Berichtswerkstatt besitzt neben `Gruppieren` nun `Dann nach`. Kategorie,
  Empfänger, Konto und Klasse/Tag können in beliebiger unterschiedlicher
  Reihenfolge kombiniert werden; gleiche oder bei ungruppierter Primäransicht
  unzulässige Kombinationen fallen sichtbar auf keine Sekundärdimension
  zurück.
- Die Engine bildet stabile Schlüssel aus Primärlabel, Sekundärlabel und
  Währung. Sichtbare Labels verwenden `Primär › Sekundär`; dieselben Gruppen
  speisen Tabelle, Drill-down, CSV, PDF und direkten Druck. Währungen bleiben
  strikt getrennt.
- `TransactionReportQuery.secondaryGrouping` ist optional und deshalb mit
  bestehenden Vorlagen ohne JSON-Feld rückwärtskompatibel. Neu über die UI
  gespeicherte Vorlagen verwenden Definitionsversion 2. Zurücksetzen,
  Laden, Filterbeschreibung und Exporttitel berücksichtigen beide Dimensionen.
- Ein neuer Test prüft drei kombinierte Kategorie-/Kontogruppen, stabile
  Positionszahlen und das Decodieren eines künstlichen Legacy-JSON ohne
  Sekundärfeld. Vorlagenrundlauf, CSV und mehrseitiges PDF wurden gemeinsam
  gezielt geprüft.
- Die vollständige Suite unter
  `/tmp/FinanzVerwalter-FullTests-ReportGrouping.xcresult` führte 83 Tests aus:
  82 bestanden, der private opt-in-QIF-Test wurde ohne Pfad erwartungsgemäß
  übersprungen, 0 Fehler. Der echte private 2025-QIF-Test bestand anschließend
  separat mit einer nur temporären, danach gelöschten Kopie.
- Der optimierte Release unter `build/DerivedData-ReportGrouping` bestand,
  wurde ad hoc signiert, streng geprüft und kontrolliert installiert. Das
  vorherige Bundle liegt reversibel unter
  `build/FinanzVerwalter-vor-zweiter-berichtsgruppe-20260731-171346.app`.
  Der neue ausführbare Code hat SHA-256
  `ed5fd2007b61ef9617d66928ca17377fc0ce2dbcaaff6217a1be6289567fcc1b`.
  Die App läuft als Prozess 63177; die Produktivdatei blieb bytegleich bei
  SHA-256 `a50877f038a9f4c18d119633dc7daa8f2464aad2369eb45df970e2a173d104f9`
  und meldet Schema 29, Integrität `ok`, 97 Konten und 2.170 Buchungen.
- Implementierung und Tests sind als Commit `6e765eb`, die reproduzierbare
  Dokumentation als `eb4b0d6` auf `agent/qif-mehrkontenimport`
  festgeschrieben und nach GitHub gepusht. Draft-PR 1 beschreibt jetzt die
  zweite Gruppierung, Vorlagenkompatibilität, 83-Test-Vollsuite und die noch
  offenen Standardberichte sowie XLSX-/HTML-Ausgaben.
- Telegram-Nachricht 975 wurde im Projektthread 894 (`/quicken`) mit demselben
  Funktions-, Test-, Release-, Datenbank- und GitHub-Stand veröffentlicht.
  Der zunächst vor dem Messaufruf eingesetzte Zählerplatzhalter wurde sofort
  auf den exakten Zielzählerstand von 11.462.415 Tokens berichtigt. Wegen der
  weiterhin gesperrten macOS-Sitzung wurde kein Screenshot angehängt oder
  vorgetäuscht.

## 2026-07-31 – Buchungsbasierte Standardberichte

- `TransactionReportStandardPreset` definiert sechs reine, testbare
  aktuelle-Jahr-Abfragen: Einnahmen/Ausgaben nach Kategorie oder Empfänger,
  Buchungsbericht, Cashflow nach Konto/Kategorie, Kontobewegungen nach
  Konto/Empfänger sowie Kategorie/Klasse. Alle verwenden die vorhandene
  Snapshot-Engine und behaupten keine noch fehlende Stichtags-, Zeitvergleichs-
  oder Budgetabweichungslogik.
- Das Menü `Standardberichte` wendet die vollständige Query sichtbar an. Titel
  und Kurzbeschreibung wechseln mit; Filter bleiben frei bearbeitbar. CSV,
  PDF und direkter Druck erhalten denselben aktiven Titel, und der Nutzer kann
  das Ergebnis als normale Definitionsversion-2-Vorlage speichern.
- Der neue deterministische Test verwendet den gregorianischen Kalender in
  `Europe/Berlin`, prüft die exakten Grenzen des Jahres 2025, sechs fachlich
  unterschiedliche Query-Signaturen sowie Buchungsjournal- und
  Cashflow-Invarianten. Gemeinsam mit Sekundärgruppierung, Vorlagenrundlauf
  und CSV-Golden-Test bestanden alle vier gezielt ausgeführten Tests.
- Die vollständige isolierte Suite unter
  `/tmp/FinanzVerwalter-FullTests-StandardReports.xcresult` führte 84 Tests
  aus: 83 bestanden, der private opt-in-QIF-Test wurde ohne lokalen Pfad
  erwartungsgemäß übersprungen, 0 Fehler. Der echte private 2025-QIF-Test
  bestand danach separat über den dafür vorgesehenen lokalen Akzeptanzpfad;
  die temporäre Kopie wurde mit `unlink` entfernt und ihr Fehlen geprüft.
- Der optimierte arm64-Release unter `build/DerivedData-StandardReports`
  bestand, wurde ad hoc signiert, streng geprüft und kontrolliert installiert.
  Das vorherige Bundle liegt reversibel unter
  `build/FinanzVerwalter-vor-standardberichten-20260731-172425.app`. Der neue
  ausführbare Code hat SHA-256
  `0fce2cb0b72ec282e74b1f1e5dcb72cc8d3368ee9d43f87faacf4a19487418c3`.
  Die App läuft als Prozess 64032; die Produktivdatei blieb bytegleich bei
  SHA-256 `a50877f038a9f4c18d119633dc7daa8f2464aad2369eb45df970e2a173d104f9`
  und meldet Schema 29, Integrität `ok`, 97 Konten und 2.170 Buchungen.
- Die Systemzustandsprüfung meldete trotz `IOConsoleLocked = No` ausdrücklich
  `CGSSessionScreenIsLocked = Yes`. Eine sichtbare UI-Abnahme oder ein neuer
  Screenshot ist daher weiterhin nicht möglich und wird nicht vorgetäuscht.
- Implementierung und Tests sind als Commit `74ef237`, die reproduzierbare
  Dokumentation als `d50c3af` auf `agent/qif-mehrkontenimport`
  festgeschrieben und nach GitHub gepusht. Draft-PR 1 dokumentiert jetzt die
  sechs Standardberichte, die 84-Test-Vollsuite und die noch offenen echten
  Stichtags- sowie Vergleichsberichte. Nach GitHubs kurzer Neuberechnung ist
  der Draft-PR wieder ausdrücklich `CLEAN` und `MERGEABLE`.
- Telegram-Nachricht 976 wurde im Projektthread 894 (`/quicken`) mit demselben
  Funktions-, Test-, Release-, Datenbank- und GitHub-Stand sowie dem exakten
  Zielzählerstand von 11.617.552 Tokens veröffentlicht. Wegen der bestätigten
  Bildschirmsperre wurde kein Screenshot angehängt oder vorgetäuscht.

## 2026-07-31 – Salden im Kontenblatt und historischer Stichtagsbericht

- Die laufende Spalte `Saldo` steht unmittelbar rechts von `Betrag` im
  Hauptkontenblatt, im zweiten Kontenblatt und in den Sammelkontenblättern.
  Vorhandene sichtbare Spaltensätze und gespeicherte Kontoblattansichten
  werden einmalig ergänzt; danach bleibt die Spalte über das Spaltenmenü frei
  konfigurierbar. Der Saldo beginnt beim Eröffnungsbestand, wird je Konto und
  Währung geführt und ignoriert stornierte Buchungen.
- Der neue Standardbericht `Kontosalden und Nettovermögen` verwendet eine
  eigene unveränderliche Stichtagsberechnung. Er berücksichtigt nur Konten,
  deren Eröffnungsdatum erreicht ist, und nur nicht stornierte Bewegungen in
  Kontowährung zwischen Eröffnung und lokalem Tagesende. Konto-, Gruppen- und
  Währungsfilter sowie Optionen für ausgeblendete, geschlossene und vom
  Nettovermögen ausgeschlossene Konten sind vorhanden.
- Die Bildschirmtabelle zeigt Gruppe, Konto, Kontotyp, Eröffnung, Bewegungen,
  Saldo und Währung. Aktiva, Passiva und Nettovermögen werden je ISO-Währung
  getrennt summiert; ohne Wechselkurs findet ausdrücklich keine Addition
  verschiedener Währungen statt.
- Deterministisches Semikolon-CSV, mehrseitiges A4-PDF in Hoch- oder
  Querformat sowie direkter macOS-Systemdruck verwenden denselben Snapshot.
  Ein PDFKit-Test prüft Titel, erste und letzte Kontozeile, Nettosumme,
  Seitenzahl und Mehrseitigkeit.
- Die finale vollständige Suite unter
  `/tmp/FinanzVerwalter-FullTests-BalanceReport-Final.xcresult` führte 87 Tests
  aus: 86 bestanden, der private opt-in-QIF-Test wurde ohne Pfad planmäßig
  übersprungen, 0 Fehler. Der echte private 2025-QIF-Test bestand danach
  separat; seine nur temporäre Kopie wurde mit `unlink` entfernt und ihr
  Fehlen geprüft.
- Der optimierte arm64-Release unter `build/DerivedData-BalanceReports`
  bestand, wurde ad hoc signiert, streng geprüft und kontrolliert installiert.
  Das vorherige Bundle liegt reversibel unter
  `build/FinanzVerwalter-vor-stichtagsbericht-20260731-174220.app`. Der neue
  ausführbare Code hat SHA-256
  `5499524da68b78adcfdd7d550ff27e412706342c3895743ffc3584b07bb98578`.
  Die App läuft als Prozess 65477; die Produktivdatei blieb bytegleich bei
  SHA-256 `a50877f038a9f4c18d119633dc7daa8f2464aad2369eb45df970e2a173d104f9`
  und meldet Schema 29, Integrität `ok`, 97 Konten und 2.170 Buchungen.
- Die Systemzustandsprüfung meldet weiterhin ausdrücklich
  `CGSSessionScreenIsLocked = Yes`. Daher war keine ehrliche sichtbare
  UI-Abnahme und kein neuer Screenshot möglich; beides wurde nicht
  vorgetäuscht. Implementierung und Tests sind in Commit `e31934a`
  festgeschrieben.
- Die reproduzierbare Dokumentation ist in Commit `dd96b46` festgeschrieben;
  beide Commits wurden auf `agent/qif-mehrkontenimport` nach GitHub gepusht.
  Draft-PR 1 beschreibt jetzt Stichtagslogik, Saldo-Spalten, 87-Test-Suite und
  die verbleibenden Zeit-/Budgetvergleiche und ist `CLEAN` sowie `MERGEABLE`.
  Telegram-Nachricht 978 wurde im Projektthread 894 (`/quicken`) mit dem
  Funktions-, Test-, Release-, Datenbank- und GitHub-Stand sowie dem exakten
  Zielzählerstand von 11.954.069 Tokens veröffentlicht. Wegen der
  Bildschirmsperre enthält sie ausdrücklich keinen vorgetäuschten Screenshot.

## 2026-07-31 – Zeitvergleich und Budget-Plan/Ist-Bericht

- `PeriodComparisonEngine` berechnet zwei frei gewählte inklusive Zeiträume
  über dieselbe unveränderliche, splitkorrekte Faktenpipeline wie die freie
  Berichtswerkstatt. Einnahmen, Ausgaben oder Saldo können nach Kategorie,
  Empfänger, Konto, Klasse/Tag oder ungruppiert gegenübergestellt werden.
  Gruppen, die nur auf einer Seite vorkommen, bleiben sichtbar; die
  Referenz ist wahlweise Summe oder Monatsdurchschnitt.
- Jede Zeile zeigt aktuellen Wert, Referenz, Differenz und auf Basispunkte
  gerundete prozentuale Änderung. Beide Zeiträume behalten getrennte
  Fakten-IDs für den Drill-down. Gesamtsummen bleiben streng nach Währung
  getrennt.
- `BudgetReportEngine` wertet wahlweise die zwölf Monate eines frei
  beginnenden Geschäftsjahres oder einen Einzelmonat aus. Berücksichtigt
  werden nur offene, budgetfähige Konten in Budgetwährung; Stornos und
  Umbuchungen werden ausgeschlossen, Splits ohne Doppelzählung expandiert.
  Direkte Kategorieanteile verhindern Elternsummen-Doppelzählung.
- Die Budgettabelle zeigt vollständige Kategoriepfade, Art, Plan, Ist,
  Abweichung und Zielerreichung. Zeilen können bei Plan und Ist null optional
  eingeblendet werden; ein Klick öffnet den Buchungs-Drill-down.
- Beide Berichte stehen im Menü `Standardberichte` bereit. Bildschirm,
  deterministisches Semikolon-CSV, mehrseitiges A4-PDF in Hoch-/Querformat
  und direkter macOS-Systemdruck verwenden denselben Snapshot einschließlich
  Summenzeilen.
- Drei neue Tests prüfen Zeitraumausrichtung, fehlende Gruppen,
  Monatsdurchschnitt, Prozentrechnung, vollständige Kategoriepfade,
  Geschäftsjahr ab Juli, Monatsauswahl, Kontenausschluss, Split-Ist,
  Drill-down, Summen sowie deterministisches CSV und ein lesbares
  mehrseitiges PDF. Die vollständige Suite unter
  `/tmp/FinanzVerwalter-FullTests-ComparisonReports-20260731-1801.xcresult`
  führte 90 Tests aus: 89 bestanden, der private opt-in-QIF-Test wurde ohne
  Pfad planmäßig übersprungen, 0 Fehler.
- Der separate Echtdatenlauf wurde anschließend ausschließlich über den
  temporären Pfad `/tmp/finanzverwalter-real-qif-acceptance.qif` gestartet.
  Das externe Volume blockierte diesmal bereits beim Systemaufruf zum Öffnen
  der Quelldatei; ein Prozess-Sample bestätigte den wartenden `open`-Aufruf.
  Der Lauf wurde beendet und der temporäre Verweis mit `unlink` entfernt.
  Es fand kein Import und keine Änderung an der Produktivdatei statt.
- Der optimierte arm64-Release unter `build/DerivedData-ComparisonReports`
  bestand und wurde streng signaturgeprüft. Das vorherige Bundle liegt
  reversibel unter
  `build/FinanzVerwalter-vor-vergleichsberichten-20260731-1808.app`. Der neue
  ausführbare Code hat SHA-256
  `856af6e2209f1d2ad9612b8af2765ff8ea393be92527e0a037f8c0a21d6ddbd6`.
  Die installierte App läuft als Prozess 67261.
- Die Produktivdatei blieb bytegleich bei SHA-256
  `a50877f038a9f4c18d119633dc7daa8f2464aad2369eb45df970e2a173d104f9`
  und meldet Schema 29, Integrität `ok`, 97 Konten und 2.170 Buchungen.
- Implementierung und Tests sind in Commit `592ac3b` festgeschrieben. Die
  Systemzustandsprüfung meldet weiterhin ausdrücklich
  `CGSSessionScreenIsLocked = Yes`; deshalb sind eine sichtbare UI-Abnahme und
  ein neuer ehrlicher Screenshot in diesem Lauf nicht möglich.
- Die reproduzierbare Dokumentation ist in Commit `90d90c7` festgeschrieben;
  beide Commits wurden auf `agent/qif-mehrkontenimport` nach GitHub gepusht.
  Draft-PR 1 beschreibt Zeit- und Budgetvergleich, 90-Test-Suite,
  Release-/Datenbankstand und den blockierten externen QIF-Dateizugriff und ist
  `CLEAN` sowie `MERGEABLE`.
- Telegram-Nachricht 979 wurde im Projektthread 894 (`/quicken`) mit demselben
  Funktions-, Test-, Release-, Datenbank- und GitHub-Stand sowie dem exakten
  Messwert von 12.312.056 Tokens veröffentlicht. Wegen der bestätigten
  Bildschirmsperre wurde kein Screenshot angehängt oder vorgetäuscht.

## 2026-08-07 – Vollständige Budgetplanung und installiertes Release

- `BudgetPlanningEngine` bildet für jedes frei beginnende Geschäftsjahr zwölf
  Monatspositionen und vollständige Kategoriepfade. Er berechnet Basisplan,
  eingehenden Übertrag, verfügbaren Plan, splitkorrektes Ist, Monatssaldo und
  ausgehenden Übertrag ausschließlich aus offenen budgetfähigen Konten in der
  Budgetwährung. Stornos und Umbuchungen bleiben ausgeschlossen.
- Roll-over kann ausgeschaltet, nur für positive Salden oder für positive und
  negative Salden aktiviert werden. Die zuletzt gesetzte Betriebsart gilt für
  Folgemonate derselben Kategorie fort, selbst wenn dort keine Planzeile
  gespeichert ist. Eine neue explizite Monatszeile kann den Modus ändern.
- Die Budgetoberfläche zeigt Basisplan, Übertrag, verfügbaren Plan, Ist, Saldo,
  Zielerreichung und Reserve. Der Jahreseditor speichert zwölf Monatswerte
  atomar. Budgets lassen sich Unicode-sicher eindeutig umbenennen, mit allen
  zwölf relativen Monatspositionen kopieren, als Folgejahr ableiten oder samt
  Planzeilen löschen; Buchungen werden beim Löschen nicht verändert.
- Der Budgetbericht verwendet denselben Snapshot für Oberfläche, Drill-down,
  deterministisches Semikolon-CSV, A4-PDF und Systemdruck. Die neuen Spalten
  und die Roll-over-Reserve sind auch im PDF-Test textuell nachgewiesen.
- Der finale Result-Bundle liegt unter
  `/tmp/FinanzVerwalter-FullTests-BudgetPlanning-Final-20260807-1002.xcresult`:
  92 Tests, 91 bestanden, der private opt-in-QIF-Test ohne konfigurierten Pfad
  planmäßig übersprungen, 0 Fehler und 0 erwartete Fehler.
- Der optimierte arm64-Release unter
  `build/DerivedData-BudgetPlanning-Release` ist streng signaturgeprüft. Sein
  ausführbarer Code hat SHA-256
  `3be65b81b4ccf15613bd3098a23732d5416e92ce96b03eb54d8eef51b1ecc4d5`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; die vorherigen Bundles
  sind reversibel unter `build/FinanzVerwalter-vor-budgetplanung-20260807-1006.app`
  und `build/FinanzVerwalter-user-vor-budgetplanung-20260807-1006.app` archiviert.
- Die App wurde sichtbar im Light Mode geöffnet, die Budgetnavigation per
  Accessibility-Baum geprüft und in
  `build/Screenshots/08-budget-release-20260807.jpeg` dokumentiert. Da in der
  Produktivdatei noch kein Budget existiert, zeigt die Aufnahme bewusst den
  geprüften Leerzustand mit der Aktion `Neu`; es wurden keine Testbudgets in
  echte Nutzerdaten geschrieben.
- Die Produktivdatei blieb vor und nach Installation bytegleich bei SHA-256
  `a50877f038a9f4c18d119633dc7daa8f2464aad2369eb45df970e2a173d104f9`.
  Schema 29 meldet Integrität `ok`, 97 Konten, 2.170 Buchungen und 782
  Kategorien. Der Fensterfuß zeigt 559 Buchungen für die aktuelle UI-Sicht;
  dies ist nicht die Gesamtzahl der Datenbank.
- Implementierung, Tests und Dokumentation wurden als Commit `dc81525` auf
  `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 trägt nun den vollständigen
  Budget-, Test-, Release- und Datenbankstand und meldet `CLEAN`.
- Telegram-Nachricht 993 wurde mit dem echten Release-Screenshot im
  Projektthread 894 (`/quicken`) veröffentlicht. Sie enthält den exakten
  Messwert von 12.795.846 Tokens; Bot-Antwort, Chat- und Thread-ID wurden
  geprüft.

## 2026-08-07 – Automatische, rotierte und migrationssichere Backups

- Der Master-Prompt wurde erneut vollständig gegen die Anforderungsmatrix
  gelesen. Als nächste lokale P0-Lücke wurde Backup/Restore priorisiert, weil
  Rotation, automatische Ausführung und Vor-Migrations-Sicherung fehlten.
- `AutomaticBackupManager` prüft beim Start und Beenden Mindestabstand und
  tatsächliche Änderung von Hauptdatei, WAL oder SHM. Standard sind 24
  Stunden, höchstens 14 Sicherungen und höchstens 90 Tage. Einstellungen und
  eine erzwungene geprüfte Sicherung sind in der Oberfläche vorhanden.
- Mengen- und Altersrotation erfassen ausschließlich Dateien mit dem
  eindeutigen Autosicherungspräfix. Manuelle und Vor-Migrations-Sicherungen
  werden nicht gelöscht. Ein vorhandenes Sicherungsziel sowie die Quelldatei
  selbst sind gegen Überschreiben geschützt; temporäre manuelle Exporte
  werden nach dem Einlesen entfernt.
- Ein gezielter Test deckte einen realen WAL-Randfall auf: Eine während der
  Erstellung gültige Sicherung konnte nach dem atomaren Verschieben ihre
  Seitendatei verlieren. Der Writer beendet nun `sqlite3_backup`, checkpointed
  WAL, wechselt das Ziel auf `journal_mode=DELETE`, finalisiert und schließt
  vollständig, entfernt Seitendateien und validiert mit `immutable=1`.
- Vor jeder Migration eines bekannten älteren Schemas entsteht eine eigene
  geprüfte Sicherung. Ein Schema größer als die aktuelle Fassung 29 wird mit
  verständlicher Meldung ohne Mutation abgewiesen. Migration 10→29 sowie die
  bestehenden Migrationen 14→29 und 22→29 sind regressionsgeprüft.
- Der finale Result-Bundle liegt unter
  `/tmp/FinanzVerwalter-FullTests-AutomaticBackup-Final-20260807-1033.xcresult`:
  94 Tests, 93 bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig
  übersprungen, 0 Fehler und 0 erwartete Fehler.
- Der optimierte arm64-Release unter
  `build/DerivedData-AutomaticBackup-Release` ist streng signaturgeprüft. Sein
  ausführbarer Code hat SHA-256
  `151949d4db1858c66b9ded293c03b36eb2bcd2301c669c853e1bed217b623d9c`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; die Vorgänger liegen
  reversibel unter `build/FinanzVerwalter-vor-autosicherung-20260807-1035.app`
  und `build/FinanzVerwalter-user-vor-autosicherung-20260807-1035.app`.
- Die installierte App läuft als Prozess 48863. Beim ersten Start erzeugte sie
  die echte Sicherung
  `Sicherungen/FinanzVerwalter-Autosicherung-20260807-083613-468-0D9A673D.qbackup`
  mit SHA-256
  `4e580a923fb8e93c18bbbdf9d325e8305a1f625a86b89fd8ca91c62479665e92`.
  Sie ist ohne WAL/SHM eigenständig lesbar, Schema 29, Integrität `ok` und
  enthält 97 Konten, 2.170 Buchungen sowie 782 Kategorien.
- Die Produktivdatei blieb bytegleich bei SHA-256
  `a50877f038a9f4c18d119633dc7daa8f2464aad2369eb45df970e2a173d104f9`
  und meldet weiterhin Integrität `ok`. Die sichtbare Einstellungsabnahme war
  wegen der erneut gesperrten macOS-Sitzung nicht möglich und wird nicht
  vorgetäuscht; Prozess-, Release- und Echtdatensicherung sind unabhängig
  davon nachgewiesen.
- Implementierung, Tests, ADR und Dokumentation wurden als Commit `15462ec`
  auf `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 enthält den vollständigen
  Sicherungs-, Test-, Release- und Echtdatenstand und meldet `CLEAN`.
- Telegram-Nachricht 994 wurde im Projektthread 894 (`/quicken`) mit dem
  exakten Messwert von 13.021.148 Tokens veröffentlicht. Wegen der bestätigten
  Bildschirmsperre wurde ausdrücklich kein neuer Screenshot vorgetäuscht.

## 2026-08-07 – Fremdwährungsbeträge und währungskorrekte Umbuchungen

- `Money` verwendet nicht mehr pauschal zwei Dezimalstellen, sondern die zur
  ISO-Währung gehörende kleinste Einheit. Sämtliche Skalierung erfolgt mit
  `Decimal` und `.bankers`; `ExchangeRate` speichert den Kurs mit dem festen
  Faktor 100.000.000 ohne binäre Fließkommazahl.
- Eine Fremdwährungsbuchung speichert Originalbetrag, Originalwährung und
  Kontowährungsbetrag gemeinsam mit einem rückprüfbaren Kurs. Teilweise
  gesetzte Felder, Nullbeträge, unterschiedliche Vorzeichen, dieselbe Währung,
  unplausible Umrechnung und eine vom Konto abweichende Buchungswährung werden
  vor dem Schreiben abgelehnt.
- Der Buchungseditor zeigt Originalbetrag, ISO-Code und Live-Kurs. In der
  zweizeiligen Kontoblattansicht steht der Originalbetrag kompakt unter dem
  gebuchten Betrag. Buchungsvorlagen erhalten diese Angaben beim
  Speichern/Laden und erzeugen weiterhin frische Entwürfe ohne Import- oder
  Transferidentität.
- Der Umbuchungsdialog nimmt bei unterschiedlichen Währungen getrennten
  Abgang und Zugang entgegen und zeigt den daraus abgeleiteten Kurs. Beide
  Seiten werden atomar in ihrer jeweiligen Kontowährung mit Gegenbetrag und
  reziprokem Kurs geschrieben. Bei gleicher Währung müssen beide Beträge
  identisch sein; geschlossene oder identische Konten sowie Nullbeträge werden
  vollständig ohne Teilbuchung abgewiesen.
- Schema 30 ergänzt `original_amount_minor`, `original_currency` und
  `exchange_rate_scaled`. Der direkte 29→30-Test beweist Erhalt bestehender
  Buchungen; auch 10→30, 14→30, 22→30 und Zukunftsschema-Ablehnung bleiben
  regressionsgeprüft.
- Der finale Result-Bundle liegt unter
  `/tmp/FinanzVerwalter-FX-full-final-8.xcresult`: 98 Tests, 97 bestanden, der
  private opt-in-QIF-Test ohne Pfad planmäßig übersprungen, 0 Fehler und 0
  erwartete Fehler. `git diff --check` ist sauber.
- Der optimierte arm64-Release unter
  `build/DerivedData-ForeignCurrency-Release` ist streng signaturgeprüft. Sein
  ausführbarer Code hat SHA-256
  `48eb2e67ab5f5871f7b12e5a9cf65e84a172436afe5a19413e5433bcb971f579`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert. Die Vorgänger liegen
  reversibel unter
  `build/FinanzVerwalter-vor-fremdwaehrung-20260807-1103.app` und
  `build/FinanzVerwalter-user-vor-fremdwaehrung-20260807-1103.app`; der
  Schreibtisch-Link zeigt weiterhin auf die Systeminstallation.
- Beim echten Start wurde die Produktivdatei auf Schema 30 migriert. Nach
  beendetem WAL-Checkpoint trägt sie SHA-256
  `e76a7733b0729bebcd85437f0bad425ecc67326e7e7df738161da18f9701e746`,
  meldet Integrität `ok` und unverändert 97 Konten, 2.170 Buchungen sowie 782
  Kategorien. Vor der Migration entstand
  `Sicherungen/FinanzVerwalter-vor-Migration-v29-20260807-090257-797-6D9ECC18.qbackup`
  mit SHA-256
  `4e580a923fb8e93c18bbbdf9d325e8305a1f625a86b89fd8ca91c62479665e92`.
  Die Datei ist Schema 29, Integrität `ok`, ohne WAL/SHM und enthält dieselben
  Objektzahlen.
- Die installierte App läuft wieder als Prozess 49965. Eine sichtbare Abnahme
  und ein neuer App-Screenshot waren wegen der bestätigten macOS-Sperre nicht
  möglich und wurden nicht vorgetäuscht. Der dokumentierte Tokenstand vor der
  Veröffentlichung beträgt exakt 13.311.533 Tokens.
- Implementierung, Tests, ADR und Dokumentation wurden als Commit `226d14c`
  auf `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 wurde auf den
  vollständigen Schema-30-, Fremdwährungs-, Release- und Echtdatenstand
  aktualisiert.
- Telegram-Nachricht 995 wurde im Projektthread 894 (`/quicken`) mit dem
  geprüften Zwischenstand und exakt 13.334.173 Tokens veröffentlicht. Die
  Nachricht nennt transparent, dass wegen der macOS-Sperre kein neuer
  Screenshot angehängt werden konnte.

## 2026-08-07 – Berichtssummen und reproduzierbarer HTML-Export

- Die buchungsbasierte Berichtswerkstatt kann Buchungsdetails, primäre
  Zwischensummen und währungsgetrennte Gesamtsummen unabhängig ein- und
  ausblenden. Die Schalter werden ab Vorlagendefinition 3 gespeichert; ältere
  JSON-Vorlagen ohne diese optionalen Felder bleiben mit allen Bereichen
  sichtbar.
- Bei einer zweiten Gruppierungsdimension folgt auf jede Primärgruppe eine
  eigene Zwischensumme. Sie enthält exakt die Vereinigung der Fakten-IDs ihrer
  Detailgruppen, sodass auch der Drill-down keine Buchung verliert oder
  doppelt zählt.
- CSV und PDF beachten dieselben Sichtbarkeitsschalter und geben Gruppen- und
  Gesamtsummen aus demselben unveränderlichen Snapshot aus. Geldbeträge
  verwenden die jeweilige ISO-Nachkommastellenzahl. Ein vollständig
  ausgeblendeter PDF-Bericht bleibt als gültiges Metadatenblatt druckbar.
- Der neue UTF-8-HTML-Export enthält Metadaten, semantische Tabellen,
  Druck-CSS, Gruppen, Zwischensummen, Buchungsdetails und Gesamtsummen gemäß
  derselben Momentaufnahme. Alle importierten Texte werden HTML-maskiert; der
  vollständige Referenzdatenstrom ist mit SHA-256
  `eade30d54725fe90fe4a00620ecac5a425e268c4900740767f69b8564f6ff8c4`
  als Golden-Test fixiert.
- Der vollständige Result-Bundle liegt unter
  `/tmp/FinanzVerwalter-Report-full-1.xcresult`: 99 Tests, 98 bestanden, der
  private opt-in-QIF-Test ohne Pfad planmäßig übersprungen, 0 Fehler und 0
  erwartete Fehler. Die fünf gezielten CSV-, HTML-, PDF-, Gruppierungs- und
  Vorlagentests waren zuvor ebenfalls vollständig grün.
- Der optimierte arm64-Release unter
  `build/DerivedData-ReportPresentation-Release` ist streng
  signaturgeprüft. Sein ausführbarer Code hat SHA-256
  `6bf5f3e3e871613136c6dd62c61ce6afff3d0eb176532a1fafdd518085c81245`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert. Die Vorgänger liegen
  reversibel unter
  `build/FinanzVerwalter-vor-berichtssummen-20260807-112339.app` und
  `build/FinanzVerwalter-user-vor-berichtssummen-20260807-112339.app`; der
  Schreibtisch-Link zeigt weiterhin auf die Systeminstallation.
- Die neue App läuft als Prozess 51044. Nach dem echten Start blieb die
  Produktivdatei bytegleich bei SHA-256
  `e76a7733b0729bebcd85437f0bad425ecc67326e7e7df738161da18f9701e746`,
  Schema 30 und Integrität `ok`; sie enthält unverändert 97 Konten, 2.170
  Buchungen und 782 Kategorien.
- Die macOS-Sitzung war bei der UI-Prüfung weiterhin gesperrt und konnte nicht
  automatisch entsperrt werden. Deshalb wurde kein Screenshot vorgetäuscht.
  Der dokumentierte Tokenstand vor der Veröffentlichung beträgt exakt
  13.577.274 Tokens.
- Implementierung, Tests, ADR und Dokumentation wurden als Commit `ba85d9e`
  auf `agent/qif-mehrkontenimport` gepusht. Draft-PR 1 wurde auf den neuen
  Berichts-, HTML-, Test-, Release- und Echtdatenstand aktualisiert.
- Telegram-Nachricht 996 wurde im Projektthread 894 (`/quicken`) mit dem
  geprüften Zwischenstand und exakt 13.589.705 Tokens veröffentlicht. Wegen
  der bestätigten Bildschirmsperre wurde ausdrücklich kein neuer Screenshot
  vorgetäuscht.

## 2026-08-07 – Echtes XLSX und zweiformatige Zwischenablage

- Die buchungsbasierte Berichtswerkstatt exportiert nun ein echtes
  SpreadsheetML-XLSX mit Metadaten, Gruppen, Zwischensummen, optionalen
  Buchungsdetails und Gesamtsummen aus demselben unveränderlichen Snapshot wie
  Bildschirm, CSV, PDF, Druck und HTML.
- Ein eigenständiger deterministischer ZIP-Writer erzeugt acht alphabetisch
  geordnete Open-XML-Bestandteile mit UTF-8-Pfaden, festen Zeitfeldern, Store-
  Kompression, CRC-32 und Zentralverzeichnis. Identische Eingaben sind
  byteidentisch; der Golden-SHA-256 lautet
  `c96f21d0d9e524b3418d1bd37aa03e5ec8c93cb3aca95ccaad8bf2ccf98186d6`.
- Geldzellen bleiben echte numerische Dezimalwerte und besitzen
  währungsabhängige Formate für null bis vier Nachkommastellen. Importierte
  Texte sind maskierte Inline-Strings, ungültige XML-Steuerzeichen werden
  entfernt und ein führendes `=` wird niemals als Formel interpretiert.
- Der explizite Befehl `Kopieren` schreibt den Bericht gleichzeitig als
  tabulatorgetrennten UTF-8-Text und als maskiertes HTML in die allgemeine
  macOS-Zwischenablage. Beide Repräsentationen verwenden denselben Snapshot.
- Der gezielte XLSX-Test prüft Paketdeterminismus, Golden-Hash, vollständige
  ZIP-CRC, XML-Wohlgeformtheit, EUR-/JPY-Zahlen, Stile, Escaping und
  Formelinjektionsschutz. Ein echter lokaler LibreOffice-Rundlauf öffnete das
  Paket, konvertierte es erfolgreich in CSV und erhielt `-1234,56` als
  locale-gerechte Zahl. Der Clipboard-Test prüft TSV und HTML gemeinsam.
- Der vollständige Result-Bundle liegt unter
  `/tmp/FinanzVerwalter-XLSX-full-1.xcresult`: 101 Tests, 100 bestanden, der
  private opt-in-QIF-Test ohne Pfad planmäßig übersprungen, 0 Fehler und 0
  erwartete Fehler.
- Der optimierte arm64-Release unter `build/DerivedData-XLSX-Release` ist
  streng signaturgeprüft. Sein ausführbarer Code hat SHA-256
  `e0320204717ac6b198ab316a56cd4902b18e35238447dcd9d48289bcbcb62d9b`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert. Die Vorgänger liegen
  reversibel unter `build/FinanzVerwalter-vor-xlsx-20260807-114408.app` und
  `build/FinanzVerwalter-user-vor-xlsx-20260807-114408.app`; der
  Schreibtisch-Link zeigt weiterhin auf die Systeminstallation. Der vor der
  finalen Dateityp-Korrektur kurz installierte Zwischenstand liegt zusätzlich
  unter `build/FinanzVerwalter-vor-xlsx-dateityp-20260807-114808.app` und der
  entsprechenden `user`-Kopie.
- Die installierte App läuft als Prozess 52961. Nach dem echten Start blieb
  die Produktivdatei bytegleich bei SHA-256
  `e76a7733b0729bebcd85437f0bad425ecc67326e7e7df738161da18f9701e746`,
  Schema 30 und Integrität `ok`; sie enthält unverändert 97 Konten, 2.170
  Buchungen und 782 Kategorien.
- Die macOS-Sitzung war weiterhin gesperrt und nicht automatisch entsperrbar.
  Deshalb wurde kein Screenshot vorgetäuscht. Der dokumentierte Tokenstand vor
  der Veröffentlichung beträgt exakt 13.816.237 Tokens.
- Der Implementierungsstand wurde mit Commit
  `8b1363ee1f231ee22db1ce9348c0f63ae6a0e0e8` (`XLSX und Berichtskopie
  ergänzen`) auf `origin/agent/qif-mehrkontenimport` veröffentlicht. Der
  bestehende Draft-PR #1 trägt nun den Titel `FinanzVerwalter: Konten,
  Zahlungsverkehr, Berichte und XLSX` und verweist auf diesen Stand.
- Ein Telegram-Zwischenstand wurde im gefundenen `/quicken`-Thread 894
  veröffentlicht. Weil die macOS-Sitzung gesperrt war, wurde dabei
  wahrheitsgemäß kein neuer Screenshot angehängt.

## 07.08.2026 – Allgemeines konfliktgeschütztes Buchungs-Undo

- Die externe Masterdatei und `docs/Anforderungsmatrix.md` wurden erneut
  abgeglichen. Als nächster P0-Slice wurde das noch fehlende allgemeine
  Buchungs-Undo vor den Anhängen umgesetzt.
- Schema 31 ergänzt `transaction_undo_runs` mit monotoner Sequenz, UUID,
  Titel, vollständigen Vorher-/Nachher-JSON-Snapshots, Buchungsanzahl sowie
  Erstellungs- und einmaligem Undo-Zeitpunkt. Die Sequenz verhindert eine
  falsche Reihenfolge mehrerer Änderungen innerhalb derselben Sekunde.
- Manuelles Erstellen und Bearbeiten, Kontowechsel, gemeinsame Kategorie-/
  Klassenorganisation, bestätigtes Löschen und Umbuchungserstellung schreiben
  das Undo-Paket atomar mit der eigentlichen Mutation. Eine gelöschte
  Umbuchungsseite erfasst und restauriert immer das vollständige Paar.
- Vor dem Undo werden Buchungen, Tags, Splits und Split-Tags deterministisch
  normalisiert und vollständig mit dem erwarteten Nachher-Snapshot verglichen.
  Fehlende oder zwischenzeitlich geänderte Buchungen brechen ohne Teilwirkung
  ab; abgeglichene Buchungen bleiben geschützt. Bei Erfolg werden Original-
  IDs und die vollständige Split-, Steuer-, Bank- und Organisationsstruktur
  restauriert, das Paket einmalig entwertet und die Aktion auditiert.
- Das Kontoblatt zeigt für das jüngste Paket einen semantisch beschrifteten
  `Rückgängig`-Button mit Titel, Anzahl, Bestätigung und verständlichem Hinweis
  auf den Konfliktschutz.
- Vier gezielte Undo-Tests und ein eigener 30→31-Migrationstest sind grün.
  Der endgültige vollständige Result-Bundle
  `/tmp/FinanzVerwalter-Undo-full-final.xcresult`
  enthält 106 Tests: 105 bestanden, der private opt-in-QIF-Test ohne Pfad
  planmäßig übersprungen, 0 Fehler und 0 erwartete Fehler.
- Der optimierte arm64-Release unter `build/DerivedData-Undo-Release` wurde
  streng signaturgeprüft. Sein ausführbarer Code hat SHA-256
  `ba065393e3a58adddc91481f352570ee7cdc703d8b39b01ee574a5bb7999f05c`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; die Vorgänger liegen
  reversibel unter `build/FinanzVerwalter-vor-undo-20260807-1207.app` und
  `build/FinanzVerwalter-user-vor-undo-20260807-1207.app`.
- Der echte Start läuft als Prozess 54910 und migrierte die Produktivdatei
  auf Schema 31. Integrität `ok` sowie 97 Konten, 2.170 Buchungen und 782
  Kategorien blieben erhalten; vor der Migration entstand die eigenständige
  Schema-30-Sicherung
  `FinanzVerwalter-vor-Migration-v30-20260807-100736-010-9095D6E2.qbackup`
  mit SHA-256
  `71643e6aa34eb06b2a596265e399e75df4a7f19c4fd4812c32d4fb8fb55327c1`,
  Integrität `ok` und identischen Nutzdatenzählungen.
- Die Computersteuerungs-Abnahme wurde erneut versucht. Die macOS-Sitzung ist
  weiterhin gesperrt und kann nicht automatisch entsperrt werden; deshalb
  konnte der neue Schalter noch nicht sichtbar geklickt und kein wahrer neuer
  Screenshot aufgenommen werden.
- Der Implementierungsstand wurde mit Commit `d9ca5c9`
  (`Konfliktgeschütztes Buchungs-Undo ergänzen`) auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht.
- Telegram-Nachricht 1003 dokumentiert den Zwischenstand im `/quicken`-Thread
  894 mit dem exakten Tokenstand 14.155.197. Sie benennt transparent, dass
  wegen der gesperrten Sitzung kein neuer Screenshot angehängt werden konnte.

## 07.08.2026 – Hashadressierte Beleganhänge an Buchungen

- Nach dem allgemeinen Undo wurde der nächste offene P0-/Härtungs-Slice aus
  Masterdatei und Anforderungsmatrix umgesetzt: produktive lokale
  Beleganhänge zunächst im Buchungseditor.
- Schema 32 ergänzt `attachment_blobs` und `attachment_links`. Originalbytes
  liegen SHA-256-adressiert direkt in der Finanzdatei, identische Inhalte
  werden global dedupliziert und Zielverknüpfungen bewahren Dateiname, MIME,
  Größe, Quelle, Zeitpunkt und getrennten künftigen OCR-Text. Repositoryseitig
  sind Konto, Buchung, Vertrag, Wertpapier und Inventar vorbereitet.
- PDF, PNG, JPEG, TXT, CSV, QIF und XML bis 50 MiB werden anhand regulärer
  Datei, Symlinkstatus, Dateiname, Dateisignatur beziehungsweise UTF-8 sowie
  eines injizierbaren Scan-Hooks vor dem atomaren Commit validiert.
  Ausführbare/unerlaubte Typen, falsche Magic Bytes, leere, übergroße oder
  während des Lesens veränderte Dateien werden abgewiesen.
- Der Buchungseditor listet mehrere Anhänge und übernimmt sie über Dateidialog
  oder Drag-and-drop. Entfernen verlangt Bestätigung. Öffnen verlangt eine
  zweite Bestätigung, verifiziert gespeicherte Größe und SHA-256 und erzeugt
  erst dann eine Vorschau mit 0700/0600-Rechten.
- Das Undo entfernt bei rückgängig gemachter Buchungserstellung inzwischen
  angefügte Belege und verwaiste BLOBs. Eine gelöschte und anschließend
  restaurierte Buchung erhält dagegen ihre erhaltene Belegverknüpfung zurück.
- Fünf neue Integrationstests prüfen Deduplizierung, Metadaten,
  Backup-Roundtrip, Vorschau und Rechte, Entfernung der letzten Referenz,
  Eingabegrenzen, Scan-Abbruch, Manipulationserkennung, Migration und beide
  Undo-Randfälle. Das endgültige vollständige Result-Bundle
  `/tmp/FinanzVerwalter-Attachments-full-final2.xcresult` enthält 111 Tests:
  110 bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig übersprungen,
  0 Fehler und 0 erwartete Fehler.
- ADR 0022 dokumentiert die bewusste SQLite-BLOB-Entscheidung. UI für Konten,
  Verträge, Wertpapiere und Inventar, offener Anhangsexport, Notizlinks und OCR
  bleiben ausdrücklich als nächste Lücken sichtbar.
- Der optimierte arm64-Release unter
  `build/DerivedData-Attachments-Release` wurde streng signaturgeprüft. Sein
  ausführbarer Code hat SHA-256
  `02e364a64657da76ceec92505cac13e0e921bc35e1ee76cf31a277880faf05b4`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  weiterhin auf die Systeminstallation. Die Vorgänger liegen reversibel unter
  `build/FinanzVerwalter-vor-anhaenge-20260807-1231.app` und
  `build/FinanzVerwalter-user-vor-anhaenge-20260807-1231.app`.
- Der echte Start läuft als Prozess 57996 und migrierte die Produktivdatei auf
  Schema 32. Integrität `ok`, 97 Konten, 2.170 Buchungen und 782 Kategorien
  blieben erhalten; neue Anhangstabellen sind erwartungsgemäß leer. Vorher
  entstand die eigenständige Schema-31-Sicherung
  `FinanzVerwalter-vor-Migration-v31-20260807-103031-672-F43B084A.qbackup`
  mit SHA-256
  `44fe9a80e922e986c795e3456c3d610d014b3622aa9a45b81c4a10291d215e56`,
  Integrität `ok` und identischen Nutzdatenzählungen.
- Die Computersteuerungs-Abnahme wurde mit der frisch installierten App erneut
  versucht. Die macOS-Sitzung blieb gesperrt und konnte nicht automatisch
  entsperrt werden; deshalb wurde kein Screenshot vorgetäuscht. Der exakte
  Zielzählerstand vor Commit und Veröffentlichung beträgt 14.426.153 Tokens.
- Implementierung und Tests wurden als Commit `6fdf9b7`, die reproduzierbare
  Dokumentation als Commit `4638c0f` auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht. Draft-PR #1 trägt nun
  den Titel `FinanzVerwalter: Konten, Zahlungsverkehr, Berichte, Undo und
  Beleganhänge`.
- Telegram-Nachricht 1007 dokumentiert denselben Stand im gefundenen
  `/quicken`-Thread 894. Sie nennt transparent die gesperrte Sitzung und den
  deshalb fehlenden Screenshot sowie den exakten Zielzählerstand 14.448.428.

## 07.08.2026 – Gemeinsame Anhangsoberfläche für alle geforderten Fachakten

- Die bisher buchungsspezifische SwiftUI-Darstellung wurde ohne Änderung des
  geprüften Schema-32-Speichers in `AttachmentManagerView` zusammengeführt.
  Dateiliste, Metadaten, Drag-and-drop, Dateiauswahl, Typinformation,
  Bestätigung, SHA-256-Vorschau und Entfernen verwenden dadurch in allen
  Fachmodulen exakt denselben Ablauf.
- Die Komponente ist nun im Buchungseditor, im Editor eines bestehenden
  Kontos, in der Vertragsdetailakte, in der Wertpapierdetailakte und in der
  Inventardetailakte eingebunden. Sie lädt beim Zielwechsel neu und entfernt
  veraltete Dialogziele. Zieltyp und UUID bilden einen stabilen AX-Identifier;
  Öffnen und Entfernen enthalten für VoiceOver den vollständigen Dateinamen.
- Ein neuer Integrationstest hängt denselben Originalbeleg gleichzeitig an
  Konto, Vertrag, Wertpapier und Inventargegenstand. Er belegt vier getrennte,
  korrekt ladbare Fachverknüpfungen bei genau einem BLOB und die physische
  Entfernung erst nach Löschung der letzten Referenz.
- Der vollständige Result-Bundle
  `/tmp/FinanzVerwalter-AllAttachments-full-final.xcresult` enthält 112 Tests:
  111 bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig übersprungen,
  0 Fehler und 0 erwartete Fehler. Debug-Build und `git diff --check` sind
  ebenfalls ohne Befund.
- Damit sind die im Master genannten Anhangsoberflächen für Konto, Buchung,
  Vertrag, Wertpapier und Inventar vorhanden. Offene Anhänge-Themen sind jetzt
  der offene Export, sichere Notizlinks und optionales OCR.
- Der optimierte arm64-Release unter
  `build/DerivedData-AllAttachments-Release` wurde streng signaturgeprüft.
  Sein ausführbarer Code hat SHA-256
  `e0fb32ec7dee787781d7801d3b944afc62861ec19052cc2639401c4d874b026d`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  weiterhin auf die Systeminstallation. Die Vorgänger liegen reversibel unter
  `build/FinanzVerwalter-vor-alle-anhaenge-20260807-1245.app` und
  `build/FinanzVerwalter-user-vor-alle-anhaenge-20260807-1245.app`.
- Der echte Start läuft als Prozess 60755. Vor und nach der Installation
  blieben Integrität `ok`, Schema 32, 97 Konten, 2.170 Buchungen, 782
  Kategorien sowie 0 Anhangs-BLOBs und 0 Anhangsverknüpfungen identisch.
- Die sichtbare Abnahme wurde mit der installierten App erneut versucht. Die
  macOS-Sitzung ist weiterhin gesperrt und kann nicht automatisch entsperrt
  werden; deshalb wurde weder ein Klickergebnis noch ein Screenshot
  vorgetäuscht. Der exakte Zielzählerstand vor Commit und Veröffentlichung
  beträgt 14.780.957 Tokens.
- Implementierung, Mehrzieltest und reproduzierbare Dokumentation wurden als
  Commit `26402dc` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  Der offene Draft-PR #1 beschreibt jetzt alle fünf Anhangsoberflächen, den
  112-Test-Nachweis und den installierten Release-Hash.
- Telegram-Nachricht 1009 dokumentiert denselben Stand im gefundenen
  `/quicken`-Thread 894. Sie nennt transparent die gesperrte Sitzung und den
  deshalb fehlenden Screenshot sowie den exakten Zielzählerstand 14.807.849.

## 07.08.2026 – Verifizierter Anhangsexport und sichere Notizlinks

- Die gemeinsame Anhangsoberfläche bietet nun in allen fünf Fachakten einen
  offenen System-Speicherdialog. Der Backendpfad verifiziert den gespeicherten
  BLOB vor dem Export erneut, schützt die Finanzdatei, erzwingt die passende
  Originalendung und akzeptiert vorhandene Ziele nur nach ausdrücklicher
  Ersetzungsfreigabe sowie nur als reguläre, nicht symbolische Datei.
- Jeder Export entsteht zuerst als neue 0600-Staging-Datei im echten
  Zielordner. Erst danach erfolgt Move oder Replace; Größe und SHA-256 des
  fertigen Ziels werden nochmals geprüft. Inkonsistente Ergebnisse werden
  entfernt, erfolgreiche Exporte mit Hash und Dateiname auditiert.
- `SecureNoteLinkPolicy` erkennt Links im unveränderten Freitext, bietet aber
  ausschließlich HTTPS mit Host und ohne eingebettete Zugangsdaten sowie
  lokale `file:`-Ziele ohne entfernten Host als Aktionen an. HTTP, FTP und
  Script-Schemata bleiben ohne Öffnungsaktion.
- `SecureNoteView` ist in Buchungsnotiz, Konto-Beschreibung, Vertrags-,
  Wertpapier- und Inventarnotiz eingebunden. Jeder Klick öffnet zunächst nur
  einen Bestätigungsdialog. Die bestätigte Aktion prüft lokale Ziele erneut
  als vorhandene reguläre, nicht symbolische und nicht ausführbare Datei;
  Verzeichnisse, Pakete, Ausführungsrechte sowie bekannte Programm-, Skript-,
  Shortcut- und Terminalendungen werden blockiert.
- Der erste Exporttest deckte eine unzulässige Foundation-Kombination aus
  atomarem Schreiben und `withoutOverwriting` auf. Da die Datei bereits ein
  eindeutiges Staging-Ziel besitzt, wurde die widersprüchliche Option entfernt;
  das atomare Move/Replace-Modell blieb erhalten. Der wiederholte gezielte
  Export- und Linktest ist grün.
- Der vollständige Result-Bundle
  `/tmp/FinanzVerwalter-SafeLinks-full.xcresult` enthält 114 Tests: 113
  bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig übersprungen,
  0 Fehler und 0 erwartete Fehler. Der saubere Debug-Build und
  `git diff --check` sind ebenfalls ohne Befund.
- Der optimierte arm64-Release unter `build/DerivedData-SafeLinks-Release`
  wurde streng signaturgeprüft. Sein ausführbarer Code hat SHA-256
  `fc868123b04d31582b6a0576ccd8b3860a7b02b128e918824b547d7bcb6df621`.
  Derselbe Stand ist unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  weiterhin auf die Systeminstallation. Die Vorgänger liegen reversibel unter
  `build/FinanzVerwalter-vor-export-links-20260807-1305.app` und
  `build/FinanzVerwalter-user-vor-export-links-20260807-1305.app`.
- Der echte Start läuft als Prozess 62483. Vor und nach der Installation
  blieben Integrität `ok`, Schema 32, 97 Konten, 2.170 Buchungen, 782
  Kategorien sowie 0 Anhangs-BLOBs und 0 Anhangsverknüpfungen identisch.
- Die sichtbare Abnahme wurde mit der installierten App erneut versucht. Die
  macOS-Sitzung ist weiterhin gesperrt und kann nicht automatisch entsperrt
  werden; deshalb wurde weder ein Klickergebnis noch ein Screenshot
  vorgetäuscht. Der exakte Zielzählerstand vor Commit und Veröffentlichung
  beträgt 15.158.044 Tokens.
- Implementierung und Tests wurden als Commit `5a04e2b`, die reproduzierbare
  Dokumentation als Commit `3ee19d7` auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht. Draft-PR #1 trägt nun
  den Titel `FinanzVerwalter: Konten, Zahlungsverkehr, Berichte, Undo und
  sichere Belege` und enthält den 114-Test- sowie Release-Nachweis.
- Telegram-Nachricht 1011 dokumentiert denselben Stand im gefundenen
  `/quicken`-Thread 894. Sie nennt transparent die gesperrte Sitzung und den
  deshalb fehlenden Screenshot sowie den exakten Zielzählerstand 15.175.982.

## 07.08.2026 – Deutscher Steuerbericht und währungssichere Diagramme

- Die buchungsbasierte Berichtswerkstatt besitzt nun den siebten
  Standardbericht `Deutscher Steuerbericht`. Er verwendet das aktuelle lokale
  Kalenderjahr, löst Splits einzeln auf, berücksichtigt ausschließlich
  Kategorien mit gepflegter deutscher Steuerzeile und gliedert zuerst nach
  Steuerzeile, dann nach dem vollständigen Kategoriepfad. Die Steuerzeile ist
  zugleich Teil der Volltextsuche und erscheint im Fakten-Drill-down dezent
  unter der Kategorie.
- Jeder freie oder gespeicherte Buchungsbericht kann als Tabelle,
  Balkendiagramm oder Tortendiagramm für Einnahmen beziehungsweise Ausgaben
  angezeigt werden. `ReportChartEngine` leitet seine Werte ausschließlich aus
  dem bereits gefilterten Snapshot ab, trennt Währungen strikt und fasst bei
  mehr als zwölf Segmenten den Rest centgenau als `Weitere (n)` mit den
  vollständigen Fakten-IDs zusammen. Die Tabelle und ihr Drill-down bleiben
  unter dem Diagramm erhalten.
- Berichtsvorlagen der Definitionsversion 4 speichern Steuerfilter,
  Darstellung und Diagrammkennzahl. Die neuen Query-Felder sind optional;
  ältere Vorlagen laden reproduzierbar ohne Steuerfilter als Tabelle mit der
  Ausgabenkennzahl.
- Vier gezielte Engine-, Preset-, Legacy- und Diagrammtests waren grün. Der
  vollständige Result-Bundle
  `/tmp/FinanzVerwalter-ReportCharts-20260807-1318.xcresult` enthält 116 Tests:
  115 bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig
  übersprungen, 0 Fehler und 0 erwartete Fehler. Debug-Build,
  `git diff --check` und der optimierte Release-Build sind ebenfalls grün.
- Der signaturgeprüfte arm64-Release liegt unter
  `build/DerivedData-ReportCharts-Release`. Sein ausführbarer Code hat
  SHA-256
  `ad5b61867e9ea68a95f274b018d2594a5a8a5557c76ad74dab4754ab6b800ebf`.
  Identische Kopien sind unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  weiter auf die Systeminstallation. Die Vorgänger bleiben reversibel unter
  `build/FinanzVerwalter-vor-steuer-diagramme-20260807-1321.app` und
  `build/FinanzVerwalter-user-vor-steuer-diagramme-20260807-1321.app`; die
  kurzzeitig installierte Vorstufe vor der Hauptwährungskorrektur liegt unter
  `build/FinanzVerwalter-vor-haupteinheiten-20260807-1326.app` und
  `build/FinanzVerwalter-user-vor-haupteinheiten-20260807-1326.app`.
- Der echte Start läuft als Prozess 64542 direkt aus `/Applications`.
  Datenintegrität `ok`, Schema 32, 97 Konten, 2.170 Buchungen, 782 Kategorien
  und eine Berichtsvorlage blieben unverändert. Der exakte Zielzählerstand vor
  der Dokumentation beträgt 15.438.166 Tokens.
- Implementierung und Tests wurden als Commit `1a714d2`, die reproduzierbare
  Dokumentation als Commit `64468b5` auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht. Draft-PR #1 enthält den
  neuen Steuer-/Diagrammumfang, den 116-Test-Nachweis und den finalen
  Release-Hash.
- Telegram-Nachricht 1013 dokumentiert denselben Stand im gefundenen
  `/quicken`-Thread 894. Wegen der nachweislich gesperrten macOS-Sitzung wurde
  transparent kein fingierter oder leerer Screenshot angehängt. Der exakte
  Zielzählerstand vor dem Versand beträgt 15.502.160 Tokens.

## 07.08.2026 – Monatlicher Cashflow sowie Linien-/Flächendiagramme

- `ReportGrouping.month` erzeugt stabile Monatsbezeichnungen im Format
  `yyyy-MM`. Der achte buchungsbasierte Standardbericht `Monatlicher Cashflow`
  verwendet das aktuelle lokale Kalenderjahr, chronologische Sortierung,
  Liniendarstellung und die Ausgabenkennzahl; alle Einstellungen bleiben wie
  bei den übrigen Presets vollständig editierbar.
- Die Berichtswerkstatt bietet nun Tabelle, Balken, Linie, Fläche und Torte.
  Linien und Flächen sortieren chronologisch und bleiben ungekürzt, damit auch
  Verläufe über mehr als zwölf Monate keine Werte verlieren. Balken und Torte
  behalten die centgenaue Top-N-Restaggregation. Alle Darstellungen leiten
  sich weiterhin ausschließlich aus dem vorhandenen, währungsgetrennten
  Snapshot ab.
- Ein neuer Engine-Test erzeugt 14 Monate von Januar 2025 bis Februar 2026 und
  belegt Reihenfolge, Vollständigkeit, exakte Minor-Unit-Summe, fehlendes
  Restsegment sowie Identität der vereinigten Fakten-IDs mit dem Snapshot.
  Der vollständige Result-Bundle
  `/tmp/FinanzVerwalter-MonthlyCharts-20260807-1334.xcresult` enthält 117 Tests:
  116 bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig
  übersprungen, 0 Fehler und 0 erwartete Fehler. `git diff --check`, gezielte
  Tests und der optimierte Release-Build sind ebenfalls grün.
- Der streng signaturgeprüfte arm64-Release liegt unter
  `build/DerivedData-MonthlyCharts-Release`. Sein ausführbarer Code hat
  SHA-256
  `ef617a912daafab1e269593c46f64609493d8529d0aa5a2959aa52e5bac6cade`.
  Identische Kopien sind unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  weiterhin auf die Systeminstallation. Die Vorgänger liegen reversibel unter
  `build/FinanzVerwalter-vor-monatsverlauf-20260807-1342.app` und
  `build/FinanzVerwalter-user-vor-monatsverlauf-20260807-1342.app`.
- Der echte Start läuft als Prozess 66151 direkt aus `/Applications`.
  Datenintegrität `ok`, Schema 32, 97 Konten, 2.170 Buchungen, 782 Kategorien
  und eine Berichtsvorlage blieben vor und nach Installation identisch. Die
  macOS-Sitzung ist weiterhin nachweislich gesperrt; deshalb wurde kein
  fingierter Screenshot erzeugt. Der exakte Zielzählerstand vor dieser
  Dokumentation beträgt 15.672.744 Tokens.
- Implementierung und Tests wurden als Commit `763d82e`, die reproduzierbare
  Dokumentation als Commit `07601bd` auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht. Draft-PR #1 enthält den
  117-Test-Nachweis, den finalen Release-Hash und die weiterhin offenen Punkte.
- Telegram-Nachricht 1018 dokumentiert denselben Stand im gefundenen
  `/quicken`-Thread 894. Sie nennt transparent die gesperrte Sitzung und den
  deshalb fehlenden Screenshot. Der exakte Zielzählerstand vor dem Versand
  beträgt 15.689.959 Tokens.

## 07.08.2026 – Zeilenweiser Umsatzsteuerbericht

- `VATReportEngine` erzeugt eine unveränderliche Momentaufnahme ausschließlich
  aus Buchungs- und Splitzeilen mit tatsächlich gespeichertem MwSt.-Schlüssel.
  Gemischte Belege werden nie über eine pauschale Belegsumme ausgewertet. Der
  Bericht trennt Brutto, Netto, Umsatzsteuer, Brutto-/Nettoeinkauf, Vorsteuer
  und Zahllast je Schlüssel und Währung und bewahrt die vollständigen Fakten-
  IDs für den Drill-down.
- Die Zuordnung der Steuerseite folgt vorrangig der Kategorieart und nicht nur
  dem Vorzeichen. Dadurch mindern negative Erlöse die Umsatzsteuer und positive
  Aufwandsrückerstattungen die Vorsteuer. Ohne Kategoriezuordnung greift ein
  dokumentierter Vorzeichen-Fallback. Frei wählbar sind Zeitraum, Konten und
  Kontengruppen, Status, Währungen, Umbuchungen sowie ausgeblendete oder von
  Berichten ausgeschlossene Konten.
- Der neue Eintrag `Umsatzsteuerbericht …` im Menü `Standardberichte` öffnet
  eine breite Schlüsselübersicht und einen geteilten Buchungs-/Split-
  Drill-down mit vollständigem Kategoriepfad. Deterministisches Semikolon-CSV
  enthält Metadaten, Schlüsselübersicht, Währungssummen und Detailpositionen.
  Mehrseitiges PDF und Systemdruck entstehen aus demselben Snapshot.
- Zwei gezielte Tests prüfen gemischte 7/19-%-Splits, Erlöse,
  Lieferantengutschriften, Kategoriepfade, EUR/USD-Trennung, exakte Summen und
  Faktenmengen sowie identische CSV-/PDF-Snapshotnutzung. Der vollständige
  Result-Bundle `/tmp/FinanzVerwalter-VATReport-20260807-1357.xcresult`
  enthält 119 Tests: 118 bestanden, der private opt-in-QIF-Test ohne Pfad
  planmäßig übersprungen, 0 Fehler und 0 erwartete Fehler. Debug-Build,
  `git diff --check` und der optimierte Release-Build sind ebenfalls grün.
- Der streng signaturgeprüfte arm64-Release liegt unter
  `build/DerivedData-VATReport-Release`. Sein ausführbarer Code hat SHA-256
  `993d6c9a3e87ec3642457cab9dfbdd6ffcd10683c3fc20da95308ac747cb0652`.
  Identische Kopien sind unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  weiter auf die Systeminstallation. Die Vorgänger liegen reversibel unter
  `build/FinanzVerwalter-vor-umsatzsteuerbericht-20260807-1402.app` und
  `build/FinanzVerwalter-user-vor-umsatzsteuerbericht-20260807-1402.app`.
- Der echte Start läuft als Prozess 68958 direkt aus `/Applications`.
  Datenintegrität `ok`, Schema 32, 97 Konten, 2.170 Buchungen, 782 Kategorien,
  eine Berichtsvorlage, 0 MwSt.-Buchungen und 0 MwSt.-Splits blieben vor und
  nach Installation identisch. Der reale QIF-Bestand erhält damit keine
  erfundenen rückwirkenden Steuerwerte. Die macOS-Sitzung ist weiterhin
  nachweislich gesperrt; deshalb wurde kein fingierter Screenshot erzeugt. Der
  exakte Zielzählerstand vor dieser Dokumentation beträgt 15.893.749 Tokens.
- Implementierung und Tests wurden als Commit `c9d797c`, die reproduzierbare
  Dokumentation als Commit `cc8479e` auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht. Draft-PR #1 enthält den
  119-Test-Nachweis, den finalen Release-Hash und die offenen Masterpunkte.
- Telegram-Nachricht 1021 dokumentiert denselben Stand im gefundenen
  `/quicken`-Thread 894. Sie nennt transparent die gesperrte Sitzung und den
  deshalb fehlenden Screenshot. Der exakte Zielzählerstand vor dem Versand
  beträgt 15.906.820 Tokens.

## 07.08.2026 – Kredit-, Zins- und Tilgungsbericht als Planbericht

- `LoanReportEngine` erzeugt aus Darlehensstammdaten, versionierten Zinssätzen,
  Gebühren und Sondertilgungen einen unveränderlichen Plan-Snapshot. Zeitraum,
  Darlehen, Währungen und inaktive Darlehen sind filterbar; verschiedene
  Währungen werden niemals addiert. Planzeilen besitzen stabile IDs aus
  Darlehens-UUID und Ratennummer.
- Der Eintrag `Kredit-, Zins- und Tilgungsbericht …` im Menü
  `Standardberichte` öffnet eine breite Darlehensübersicht. Der Drill-down
  zeigt den vollständigen Ratenplan und eine Restschuldlinie. CSV,
  mehrseitiges A4-PDF und Systemdruck verwenden denselben Snapshot. UI und
  Exporte kennzeichnen ausdrücklich `Planwerte – kein Ist-Zahlungsabgleich`;
  automatische Ratensplits, Ist-Matching und Szenarien bleiben offen.
- Zwei neue Tests prüfen Periodenfilter, Zins, Gebühr, Sondertilgung,
  Restschuldinvariante, stabile IDs, EUR/USD-Trennung, deterministisches CSV
  und ein semantisch lesbares mehrseitiges PDF. Der vollständige Result-Bundle
  `/tmp/FinanzVerwalter-LoanReport-Full-20260807-1414.xcresult` enthält 121
  Tests: 120 bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig
  übersprungen, 0 Fehler und 0 erwartete Fehler. Gezielte Tests,
  `git diff --check`, Debug- und optimierter Release-Build sind ebenfalls grün.
- Der streng signaturgeprüfte arm64-Release liegt unter
  `build/DerivedData-LoanReport-Release`. Sein ausführbarer Code hat SHA-256
  `ef0dd2f0f8e41a7cdc4b0a7d78fd8a1da75829a804928d627434068b74473c18`.
  Identische Kopien sind unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt auf
  die Systeminstallation. Die Vorgänger liegen reversibel unter
  `build/FinanzVerwalter-vor-kreditbericht-20260807-1419.app` und
  `build/FinanzVerwalter-user-vor-kreditbericht-20260807-1419.app`.
- Der echte Start läuft als Prozess 70913 direkt aus `/Applications`.
  Datenintegrität `ok`, Schema 32, 97 Konten, 2.170 Buchungen, 782 Kategorien
  und eine Berichtsvorlage blieben unverändert. Der Bestand enthält 0
  Darlehen, Zinssätze, Sondertilgungen und Zahlungszuordnungen; deshalb zeigt
  der Bericht dort korrekt keine erfundenen Kreditdaten. Die macOS-Sitzung ist
  weiterhin nachweislich gesperrt, sodass kein fingierter Screenshot erzeugt
  wurde. Der exakte Zielzählerstand vor dieser Dokumentation beträgt
  16.106.564 Tokens.
- Implementierung und Tests wurden als Commit `392d80d`, die reproduzierbare
  Dokumentation als Commit `5b8fb30` auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht. Draft-PR #1 enthält den
  121-Test-Nachweis, Release-Hash und die weiterhin offenen Masterpunkte.
- Telegram-Nachricht 1024 dokumentiert denselben Stand im gefundenen
  `/quicken`-Thread 894. Sie nennt transparent die gesperrte Sitzung und den
  deshalb fehlenden Screenshot. Der exakte Zielzählerstand nach dem Versand
  beträgt 16.114.449 Tokens.

## 07.08.2026 – Einzelne Serieninstanzen ändern und überspringen

- Der Kalender kann eine einzelne Instanz eines regelmäßigen Vorgangs jetzt
  dauerhaft ändern oder überspringen. Der Editor erlaubt Datum, Empfänger,
  Verwendungszweck, vollständige Kategorie einschließlich `keine Kategorie`,
  Betrag und Notiz. Geänderte und übersprungene Termine bleiben in
  `Serienausnahmen` sichtbar und lassen sich einzeln auf den Serienwert
  zurücksetzen.
- Migration 33 ergänzt `scheduled_transaction_exceptions` mit genau einer
  Ausnahme je Serie und ursprünglichem Fälligkeitsdatum. Eine verschobene
  Instanz behält ihre stabile Ursprungskennung. Dadurch wird sie weder neu
  erzeugt noch bei vorhandener Materialisierung doppelt gezählt. Speichern,
  Aktualisieren, Rücksetzen und Audit sind atomar; ungültige Termine werden
  ohne Teiländerung abgelehnt. Änderungen an dieser und allen zukünftigen
  Instanzen, Wochenansicht, Drag-and-drop und Szenarien bleiben offen.
- Zwei neue Tests prüfen vollständiges Ändern, Kategorieentfernung,
  Überspringen, Neustartpersistenz, stabile Identität, Deduplizierung,
  eindeutiges Aktualisieren, atomare Ablehnung, Rücksetzen und die Migration
  32 auf 33. Der abschließende Result-Bundle
  `/tmp/FinanzVerwalter-ScheduledExceptions-final-20260807.xcresult` enthält
  123 Tests: 122 bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig
  übersprungen, 0 Fehler und 0 erwartete Fehler. `git diff --check` und der
  optimierte arm64-Release-Build sind ebenfalls grün.
- Der streng signaturgeprüfte Release liegt unter
  `build/DerivedData-ScheduledExceptions-Release`. Sein ausführbarer Code hat
  SHA-256
  `2959b372cf6285b11e85c4b60a5d5f24ccbf636acf304d6454d2ec9fbd292c64`.
  Identische Kopien sind unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  auf die Systeminstallation. Die Vorgänger liegen reversibel unter
  `build/FinanzVerwalter-vor-serienausnahmen-20260807-1441.app` und
  `build/FinanzVerwalter-user-vor-serienausnahmen-20260807-1441.app`.
- Der echte Start läuft als Prozess 73325 direkt aus `/Applications`. Die
  produktive Datei wurde automatisch von Schema 32 auf 33 migriert:
  Datenintegrität `ok`, 97 Konten, 2.170 Buchungen, 782 Kategorien und eine
  Berichtsvorlage blieben unverändert; der Bestand enthält 0 Serientermine
  und 0 Serienausnahmen. Die automatisch erstellte Vor-Migrationssicherung
  `FinanzVerwalter-vor-Migration-v32-20260807-123955-335-388E7FA0.qbackup`
  wurde separat mit Integrität `ok`, Schema 32 und identischen Kernzählungen
  geprüft.
- Implementierung und Tests wurden als Commit `dd14897`, die reproduzierbare
  Dokumentation als Commit `f42f3cc` angelegt. Die macOS-Sitzung ist
  nachweislich gesperrt; deshalb wurde kein fingierter Screenshot erzeugt.
  Der exakte Zielzählerstand vor dieser Dokumentation beträgt 16.384.191
  Tokens.
- GitHub Draft-PR #1 wurde mit Head `dd3baa3`, dem 123-Test-Nachweis und dem
  installierten Release-Hash aktualisiert. Telegram-Nachricht 1026 meldet
  denselben Stand im gefundenen `/quicken`-Thread 894 und erklärt transparent
  den wegen der gesperrten Sitzung fehlenden Screenshot. Der exakte
  Zielzählerstand nach dem Versand beträgt 16.416.968 Tokens.

## 07.08.2026 – Diese und alle folgenden Serientermine ändern

- Der Editor einer virtuellen Serienfälligkeit trennt jetzt klar zwischen
  `Änderung speichern` für genau eine Instanz und `Diesen und alle folgenden
  ändern`. Die zweite Aktion besitzt einen Bestätigungsdialog und übernimmt
  Datum, Empfänger, Verwendungszweck, vollständige Kategorie einschließlich
  `keine Kategorie`, Betrag und Notiz ab dem gewählten Termin. Die vorhandene
  Frequenz läuft vom neuen Datum aus weiter.
- Migration 34 ergänzt `scheduled_transaction_revisions` mit genau einem
  versionierten Änderungspunkt je Serie und ursprünglicher Fälligkeit. Die
  logische Serien-ID und die positionsgleiche ursprüngliche Herkunftskennung
  bleiben erhalten. Dadurch erkennen Prognose und Materialisierung auch
  verschobene Folgetermine ohne Doppelzählung. Spätere Revisionen lösen den
  Verlauf erneut ab; spätere Einzelausnahmen übersteuern genau eine revidierte
  Instanz. Beide Ebenen sind sichtbar und getrennt rücksetzbar.
- Speichern einer Serienrevision ersetzt eine Einzelausnahme am identischen
  Ursprungstermin atomar und schreibt für beide Mutationen ein eigenes
  Auditereignis. Widersprüchliche IDs und Termine außerhalb der kanonischen
  Serie werden ohne Teiländerung abgelehnt.
- Der abschließende Result-Bundle
  `/tmp/FinanzVerwalter-ScheduledRevisions-full-2-20260807.xcresult` enthält
  125 Tests: 124 bestanden, der private opt-in-QIF-Test ohne Pfad planmäßig
  übersprungen, 0 Fehler und 0 erwartete Fehler. Neue Tests prüfen zwei
  aufeinanderfolgende Revisionen, neu verankerte Monatsfolgen,
  Kategorieentfernung, stabile Referenzen, Deduplizierung,
  Einzelübersteuerung, atomaren Ausnahmeersatz samt Audit, Update mit stabiler
  ID, ungültige Grenzen, Rücksetzen sowie Migration 33 auf 34. Debug-Build,
  `git diff --check` und optimierter arm64-Release-Build sind ebenfalls grün.
- Der streng signaturgeprüfte Release liegt unter
  `build/DerivedData-ScheduledRevisions-Release`. Sein ausführbarer Code hat
  SHA-256
  `47f3c9eb501218c7f1fae6b2c213a20b0c95f31ee091ea9d1904070b31d6067e`.
  Identische Kopien sind unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  weiter auf die Systeminstallation. Die Vorgänger liegen reversibel unter
  `build/FinanzVerwalter-vor-serienrevisionen-20260807-1509.app` und
  `build/FinanzVerwalter-user-vor-serienrevisionen-20260807-1509.app`.
- Der echte Start läuft als Prozess 77225 direkt aus `/Applications`. Die
  produktive Datei wurde automatisch von Schema 33 auf 34 migriert:
  Datenintegrität `ok`, 97 Konten, 2.170 Buchungen, 782 Kategorien und eine
  Berichtsvorlage blieben unverändert; der reale Bestand enthält 0
  Serientermine, 0 Einzelausnahmen und 0 Serienrevisionen. Die automatische
  Vor-Migrationssicherung
  `FinanzVerwalter-vor-Migration-v33-20260807-130902-172-A2150DF6.qbackup`
  wurde separat mit Integrität `ok`, Schema 33 und identischen Kernzählungen
  geprüft.
- Implementierung und Tests wurden als Commit `07f006d`, die reproduzierbare
  Dokumentation als Commit `b67acb0` angelegt. Die macOS-Sitzung ist weiterhin
  nachweislich gesperrt; deshalb wurde kein fingierter Screenshot erzeugt.

## 07.08.2026 – Monats-, Wochen- und Listenansicht im Finanzkalender

- `Kalender & Prognose` bietet jetzt die drei segmentierten Ansichten `Monat`,
  `Woche` und `Liste`. Monat und Woche beginnen am Montag. Das Monatsraster
  umfasst alle berührten Wochen einschließlich sichtbar abgeschwächter
  Randtage; eine Woche besitzt exakt sieben Tage. `Heute` sowie Vor-/Zurück-
  Navigation wechseln den fokussierten Zeitraum.
- Reale Buchungen und die bereits deduplizierten virtuellen Serientermine
  werden für das Raster zusammengeführt, ohne ihre Persistenz zu verändern.
  Eine Legende und dieselben Farben in jeder Zelle unterscheiden regelmäßig,
  erwartet, vorgemerkt, gebucht und storniert. Bestätigte und abgeglichene
  Buchungen gehören dabei bewusst zur Klasse `Gebucht`; virtuelle Termine
  bleiben aus der bestehenden Oberfläche einzeln bearbeitbar.
- Konto-, Kategorie- und Klassen-/Tag-Filter sind kombinierbar. Kategorie und
  Klasse erscheinen als vollständiger Hierarchiepfad; ein gewählter
  Oberknoten schließt alle Nachfahren ein. Direkte Zuordnungen und sämtliche
  Splitzeilen werden geprüft. Kalenderzellen, Hilfetexte und
  Accessibility-Beschriftungen behalten Konto, vollständigen Kategoriepfad,
  Status, Datum und Betrag bei.
- Die reine `FinanceCalendarLayout`-Logik sowie die Statusklassifikation sind
  ohne Oberfläche testbar. Die neuen Tests decken Februar 2024 mit 29
  Monatstagen und Randtagen vom 29.01. bis 03.03., die Woche vom 29.12.2025
  bis 04.01.2026, Monats- und Wochenverschiebung über den Jahreswechsel sowie
  alle Transaktionsstatus ab.
- Das Result-Bundle
  `/tmp/FinanzVerwalterCalendarDD/Logs/Test/Test-FinanzVerwalter-2026.08.07_15-21-14-+0200.xcresult`
  enthält 127 Tests: 126 bestanden, der private opt-in-QIF-Test ohne Pfad
  planmäßig übersprungen, 0 Fehler und 0 erwartete Fehler. Der Debug-Build,
  gezielte Kalenderlauf, vollständige Suite, `git diff --check` und der
  optimierte arm64-Release-Build sind grün.
- Der streng signaturgeprüfte Release liegt unter
  `build/DerivedData-FinanceCalendar-Release`. Sein ausführbarer Code hat
  SHA-256
  `31bfa45b704a46df32ca3322179feb5454c180e80a95f9b076e80d2fe0fd6c6d`.
  Identische Kopien sind unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` installiert; der Desktop-Link zeigt
  auf die Systeminstallation. Die Vorgänger sind reversibel unter
  `build/FinanzVerwalter-vor-finanzkalender-20260807-1527.app` und
  `build/FinanzVerwalter-user-vor-finanzkalender-20260807-1527.app` erhalten.
- Der echte Start läuft als Prozess 81296 direkt aus `/Applications`. Die
  produktive Datei blieb auf Schema 34 und besitzt Integrität `ok`; 97 Konten,
  2.170 Buchungen, 782 Kategorien, eine Berichtsvorlage und jeweils 0 Serien,
  Einzelausnahmen und Serienrevisionen sind unverändert. Es gab keine
  Datenmigration.
- Die Implementierung samt Tests wurde als Commit `406e9c4` angelegt. Die
  macOS-Sitzung ist weiterhin nachweislich gesperrt
  (`CGSSessionScreenIsLocked=true`); deshalb wurde kein irreführender oder
  fingierter App-Screenshot erzeugt. Direktes Kalender-Drag-and-drop und
  Was-wäre-wenn-Szenarien bleiben gemäß Anforderungsmatrix offen.
- Der exakte kumulative Zielzählerstand nach Installation und Produktivprüfung
  beträgt 16.922.518 Tokens.
- Die reproduzierbare Dokumentation wurde als Commit `987eda4` angelegt und
  zusammen mit `406e9c4` auf `origin/agent/qif-mehrkontenimport` gepusht.
  GitHub Draft-PR #1 zeigt diesen Stand, ist konfliktfrei und als mergebar
  ausgewiesen.
- Telegram-Nachricht 1034 meldet Test-, Release-, Installations-, Datenbank-
  und GitHub-Stand im gefundenen `/quicken`-Thread 894. Sie nennt transparent
  die Bildschirmsperre als Grund für den fehlenden echten Screenshot. Der
  exakte kumulative Zielzählerstand nach dem Versand beträgt 16.941.246 Tokens.

## 07.08.2026 – Validiertes Kalender-Drag-and-drop

- Erwartete Buchungen ohne verknüpftes Umbuchungspaar und virtuelle
  regelmäßige Termine können in Monats- und Wochenansicht auf einen anderen
  Kalendertag gezogen werden. Alle anderen Status sind keine Drag-Quellen.
  Vor der Mutation nennt ein Bestätigungsdialog Vorgang, Quell- und Zieldatum.
- Die reine `FinanceCalendarMovePolicy` lehnt Ziele vor dem heutigen lokalen
  Tag, denselben Tag, gebuchte Zustände, Umbuchungspaare und ungültige
  Serienreferenzen ab. Bei einer erwarteten realen Buchung folgt die
  Wertstellung nur dann dem neuen Buchungsdatum, wenn sie zuvor mit diesem
  zusammenfiel; ein abweichendes Wertstellungsdatum bleibt erhalten. Die
  vollständige Buchung wird über den vorhandenen Audit-/Undo-Pfad gespeichert.
- Ein virtueller Serientermin wird als persistente `modified`-Einzelausnahme
  verschoben. Serien-ID, ursprüngliche Fälligkeit, Ausnahme-ID, Erstellzeit
  und vorhandene Notiz bleiben bei erneutem Verschieben stabil; dadurch
  funktionieren Deduplizierung und Rücksetzen unverändert.
- Der vollständige Result-Bundle
  `/tmp/FinanzVerwalterCalendarDragDD/Logs/Test/Test-FinanzVerwalter-2026.08.07_15-35-18-+0200.xcresult`
  enthält 129 Tests: 128 bestanden, der private opt-in-QIF-Test ohne Pfad
  planmäßig übersprungen, 0 Fehler und 0 erwartete Fehler. Gezielte Tests
  prüfen sämtliche Verbote, mitlaufende und unabhängige Wertstellung,
  normalisiertes Zieldatum, stabile Serienausnahme und ungültige Referenz.
  Debug-Build, Vollsuite, `git diff --check` und optimierter arm64-Release sind
  grün.
- Der signaturgeprüfte Release liegt unter
  `build/DerivedData-CalendarDrag-Release`; SHA-256 des ausführbaren Codes ist
  `66801bd43e8cbe8d513e37356af29dc1aea96945f025521bc83e153b07f2854a`.
  Identische Kopien liegen unter `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app`. Die Vorgänger sind reversibel als
  `build/FinanzVerwalter-vor-kalenderdrag-20260807-1540.app` und
  `build/FinanzVerwalter-user-vor-kalenderdrag-20260807-1540.app` erhalten.
- Der echte Start läuft als Prozess 83581 aus `/Applications`. Produktivdatei:
  Schema 34, Integrität `ok`, unverändert 97 Konten, 2.170 Buchungen,
  782 Kategorien, eine Berichtsvorlage und jeweils 0 Serien, Einzelausnahmen
  und Serienrevisionen. Die Sitzung ist weiterhin gesperrt, weshalb kein
  fingierter Screenshot erzeugt wurde. Exakter kumulativer Zielzählerstand
  nach Installation und Produktivprüfung: 17.059.375 Tokens.
- Implementierung und Tests wurden als Commit `cae4bf1`, Dokumentation als
  `abfca28` angelegt und auf den Arbeitsbranch gepusht. Draft-PR #1 enthält
  den aktuellen 129-Test-Nachweis und ist konfliktfrei/mergebar.
- Telegram-Nachricht 1036 meldet Drag-and-drop, Validierung, Test-, Release-,
  Installations-, Datenbank- und GitHub-Stand im `/quicken`-Thread 894. Der
  exakte kumulative Zielzählerstand nach Versand und PR-Prüfung beträgt
  17.069.149 Tokens.
  Der exakte Zielzählerstand vor dieser Dokumentation beträgt 16.682.116
  Tokens.
- GitHub Draft-PR #1 wurde konfliktfrei mit Head `4ed8485`, dem
  125-Test-Nachweis und dem installierten Release-Hash aktualisiert.
  Telegram-Nachricht 1030 meldet denselben Stand im gefundenen
  `/quicken`-Thread 894 und erklärt transparent den wegen der gesperrten
  Sitzung fehlenden Screenshot. Der exakte Zielzählerstand nach dem Versand
  beträgt 16.696.712 Tokens.

## 07.08.2026 – Persistente Liquiditätsszenarien

- SQLite-Schema 35 speichert benannte, aktivierbare Szenarien und ihre
  konto-, datums- und währungsbezogenen manuellen Positionen. Fremdschlüssel,
  Kaskadenlöschung, Versionen und Audit schützen den Lebenszyklus; die
  Migration 34→35 erhält bestehende Konten und Buchungen.
- Die reine `LiquidityForecastEngine` berechnet Tages-, ISO-Wochen- und
  Monatsintervalle für ein Konto, eine Kontengruppe oder alle offenen
  Prognosekonten exakt einer Währung. Jedes Intervall enthält Anfang,
  Bewegung, Schluss, Minimum, Maximum und alle ursächlichen Positionen.
- Herkunft ist für gebuchte, vorgemerkte und erwartete Buchungen,
  Zahlungsaufträge, Daueraufträge, allgemeine Serientermine und
  Szenarioannahmen sichtbar. Reale Positionen haben bei identischem starken
  Schlüssel Vorrang vor Zahlungsauftrag, Dauerauftrag und Serientermin;
  Szenarioannahmen bleiben bewusst additiv.
- Die Szenarioverwaltung bietet Basisvergleich, 30/90/365 Tage,
  Tages-/Wochen-/Monatsintervall, Währungs- und Bereichsauswahl,
  Schlusssaldo, Minimum, Maximum, Unterdeckungen und Szenarioeffekt. Die
  Betragseingabe folgt den Nachkommastellen der gewählten Kontowährung.
- Der finale vollständige Debug-Testlauf vom 07.08.2026 um 16:04 Uhr ist grün:
  131 Tests bestanden, der private opt-in-QIF-Test wurde ohne gesetzten Pfad
  planmäßig übersprungen, 0 Tests schlugen fehl. Er prüft unter anderem
  Deduplizierung der Prognosequellen, Mehrwährungsschutz, Intervallgrenzen,
  Persistenz/Audit/Kaskade und Migration 34→35. Das Result-Bundle liegt unter
  `build/DerivedData-ForecastScenario-Tests/Logs/Test/Test-FinanzVerwalter-2026.08.07_16-04-06-+0200.xcresult`.
- Der optimierte arm64-Release unter
  `build/DerivedData-ForecastScenarios-Release` ist gebaut und streng
  signaturgeprüft. Der ausführbare Code trägt SHA-256
  `5e3c3e4477f71095c986f9fcd257426eca3629bd915c18ad1d6004f979d5fd83`;
  Release, `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich. Der Desktop-Link
  zeigt weiter auf die Systeminstallation.
- Vor der Installation wurden beide vorherigen Apps reversibel als
  `build/FinanzVerwalter-vor-liquiditaetsszenarien-20260807-1610.app` und
  `build/FinanzVerwalter-user-vor-liquiditaetsszenarien-20260807-1610.app`
  erhalten. Der echte neue Start läuft als Prozess 89227 direkt aus
  `/Applications`.
- Die produktive Datei wurde automatisch von Schema 34 auf 35 migriert und
  hat Integrität `ok`. Unverändert sind 97 Konten, 2.170 Buchungen,
  782 Kategorien, eine Berichtsvorlage und jeweils 0 Serien,
  Einzelausnahmen und Serienrevisionen; neu und erwartungsgemäß leer sind
  Szenarien und Szenariopositionen. Die automatisch erzeugte Sicherung
  `FinanzVerwalter-vor-Migration-v34-20260807-140952-538-B24D5678.qbackup`
  ist separat mit Schema 34, Integrität `ok` und denselben Bestandszahlen
  verifiziert.
- Die macOS-Sitzung ist weiterhin gesperrt. Die installierte App konnte
  deshalb nicht sichtbar per Computersteuerung abgenommen und es wurde kein
  fingierter Screenshot erzeugt. Exakter kumulativer Zielzählerstand nach
  Test, Release, Installation und Produktivprüfung: 17.401.704 Tokens.
- Implementierung und Tests wurden als Commit `a2b70a5`, Architektur- und
  Reproduktionsdokumentation als `218a0b6` und diese Releasebelege als
  `b7021dd` auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub
  Draft-PR #1 ist mit Head `b7021dd` aktualisiert, offen, konfliktfrei und
  mergebar; die Beschreibung nennt 132 Tests, Schema 35 und den installierten
  Release-Hash.
- Telegram-Nachricht 1042 meldet Funktions-, Test-, Release-, Installations-,
  Migrations- und GitHub-Stand im gefundenen `/quicken`-Thread 894. Sie weist
  ausdrücklich darauf hin, dass wegen der weiterhin gesperrten Sitzung kein
  veralteter oder fingierter Screenshot gesendet wurde. Exakter kumulativer
  Zielzählerstand unmittelbar vor dem Versand: 17.435.457 Tokens.

## 07.08.2026 – Kontenschnellaktionen und sicherer Kontolebenszyklus

- Die Kontenübersicht besitzt jetzt kontoabhängige Toolbar-Aktionen für
  Kontoblatt, schreibgeschützten Abruf, Abgleich und Bearbeitung. Die zuvor
  wirkungslose Kontextaktion „Im Kontoblatt öffnen“ navigiert nun mit der
  gewählten Konto-ID wirklich zum Kontoblatt; Onlinekonten gelangen analog
  direkt in den Banking-Bereich.
- Tabelle und Kontextmenü zeigen zusätzlich den letzten Abruf und bieten
  Ein-/Ausblenden, Schließen und Wiederöffnen. Vor dem Schließen nennt der
  Bestätigungsdialog den aktuellen Saldo sowie die Anzahl aktiver
  regelmäßiger Vorgänge, Daueraufträge und noch offener Zahlungsaufträge.
  Der vorhandene auditierte `saveAccount`-Pfad erhält sämtliche Buchungen.
  Ausgeblendete oder geschlossene Konten bleiben nicht versehentlich als
  globale aktive Kontoauswahl gesetzt.
- `AccountClosureImpact` kapselt die reproduzierbare, kontengenaue
  Offene-Posten-Ermittlung. Der neue Test prüft, dass fremde Konten,
  deaktivierte Serien, pausierte Daueraufträge und endgültig angenommene,
  abgelehnte oder abgebrochene Zahlungsaufträge nicht gezählt werden.
- Der vollständige Debug-Testlauf vom 07.08.2026 um 16:18 Uhr ist grün:
  132 Tests bestanden, der private opt-in-QIF-Test wurde ohne gesetzten Pfad
  planmäßig übersprungen, 0 Tests schlugen fehl. Das Result-Bundle liegt unter
  `build/DerivedData-AccountOverviewQuickActions/Logs/Test/Test-FinanzVerwalter-2026.08.07_16-18-43-+0200.xcresult`.
- Der optimierte arm64-Release unter
  `build/DerivedData-AccountQuickActions-Release` wurde erfolgreich gebaut,
  lokal ad-hoc signiert und streng geprüft. Der ausführbare Code trägt
  SHA-256 `d766f1f3412cadb74c60691974ad1e4b3be6a0068a0b4a852be0ebefcb43ffca`;
  Release, `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich.
- Die beiden Vorgängerinstallationen sind reversibel als
  `build/FinanzVerwalter-vor-kontenschnellaktionen-20260807-162340.app` und
  `build/FinanzVerwalter-user-vor-kontenschnellaktionen-20260807-162340.app`
  erhalten. Der Desktop-Link zeigt auf die Systeminstallation; der neue
  Prozess 92524 läuft direkt aus `/Applications/FinanzVerwalter.app`.
- Die produktive Datei blieb unverändert bei Schema 35 und Integrität `ok`:
  97 Konten, 2.170 Buchungen, 782 Kategorien und erwartungsgemäß keine
  Szenarien oder Szenariopositionen. Die macOS-Sitzung ist weiterhin
  gesperrt; deshalb war keine ehrliche sichtbare UI-Abnahme oder ein aktueller
  Screenshot möglich. Exakter kumulativer Zielzählerstand nach Test, Release,
  Installation und Produktivprüfung: 17.643.074 Tokens.
- Implementierung, Test und Reproduktionsdokumentation sind als Commit
  `5ee967b` auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub
  Draft-PR #1 nennt nun den 133-Test-Nachweis, den neuen Release-Hash und die
  Kontenschnellaktionen; er ist offen, konfliktfrei und mergebar.
- Telegram-Nachricht 1045 meldet denselben verifizierten Stand im
  `/quicken`-Thread 894 und erklärt ausdrücklich den wegen der gesperrten
  Sitzung fehlenden Screenshot. Exakter kumulativer Zielzählerstand nach
  Telegram-, GitHub- und Prozessprüfung: 17.666.801 Tokens.

## 07.08.2026 – Vertrags- und Inventarübersicht

- Das Menü `Standardberichte` öffnet jetzt eine eigenständige Vertrags- und
  Inventarübersicht aus einem unveränderlichen gemeinsamen Snapshot. Kombiniert
  werden Aktivstatus, Vertragstypen, Inventarkategorien,
  diakritikaunabhängiger Volltext und Kündigungs-/Garantiehorizonte für alle
  oder die nächsten 30, 90 beziehungsweise 365 Tage.
- Vertragszeilen zeigen Anbieter, Vertragsnummer, Typ, Jahreskosten, nächste
  Verlängerung, Kündigungsfrist, Zahlungskonto und vollständigen
  Kategoriepfad. Inventarzeilen zeigen Kategorie, Raum, Kaufpreis, aktuellen
  Wert, Versicherungswert, Garantieende, Händler und Seriennummer. Auswahl
  liefert einen kompakten Zeilen-Drill-down; abgelaufene Fristen werden
  farblich markiert.
- Semikolon-CSV, A4-PDF in beiden Ausrichtungen und Systemdruck verwenden
  denselben Snapshot und dieselben Filtermetadaten. Da das vorhandene
  Vertrags-/Inventarmodell noch kein Währungsfeld besitzt, weist der Bericht
  diese Werte ehrlich und explizit als EUR aus.
- Der gezielte Golden-Test prüft Status-/Typ-/Kategorie-/Fristfilter,
  vollständige Kategoriehierarchie, Jahreskosten, Kauf-/aktuelle/
  Versicherungswerte, CSV-Escaping und semantisch lesbaren PDF-Inhalt. Der
  finale Einzeltest bestand unter
  `build/DerivedData-AssetRegisterReport/Logs/Test/Test-FinanzVerwalter-2026.08.07_16-44-09-+0200.xcresult`.
- Die vollständige Regression vom 07.08.2026 um 16:36 Uhr ist grün: 133 Tests
  bestanden, der private opt-in-QIF-Test wurde ohne gesetzten Pfad planmäßig
  übersprungen, 0 Tests schlugen fehl. Das Result-Bundle liegt unter
  `build/DerivedData-AssetRegisterReport/Logs/Test/Test-FinanzVerwalter-2026.08.07_16-36-14-+0200.xcresult`.
- Der optimierte arm64-Release unter
  `build/DerivedData-AssetRegisterReport-Release` wurde erfolgreich gebaut,
  lokal ad-hoc signiert und streng geprüft. Der ausführbare Code trägt
  SHA-256 `a7ed148c66eaeeecd605bb72be97f1a529cba5eabbafd549e3772de084e358dc`;
  Release, `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich.
- Die Vorgängerinstallationen wurden reversibel als
  `build/FinanzVerwalter-vor-vertrags-inventarbericht-20260807-164930.app`
  und
  `build/FinanzVerwalter-user-vor-vertrags-inventarbericht-20260807-164930.app`
  erhalten. Der neue Prozess 96275 läuft direkt aus `/Applications`; der
  Desktop-Link zeigt weiterhin auf diese Systeminstallation.
- Die produktive Datei blieb bei Schema 35 und Integrität `ok`: 97 Konten,
  2.170 Buchungen, 782 Kategorien sowie derzeit 0 Verträge, 0
  Inventargegenstände und 0 Szenarien. Die macOS-Sitzung ist weiterhin
  gesperrt; deshalb konnte der neue Bericht nicht ehrlich sichtbar abgenommen
  und kein aktueller Screenshot erzeugt werden. Exakter kumulativer
  Zielzählerstand nach Test, Release, Installation und Produktivprüfung:
  17.922.308 Tokens.
- Implementierung und Reproduktionsdokumentation wurden als Commit `da15f2d`,
  die Releasebelege als `e3da91e` auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub Draft-PR #1 ist
  mit Head `e3da91e` aktualisiert, offen und nach abschließender REST-Prüfung
  konfliktfrei/mergebar.
- Telegram-Nachricht 1048 meldet denselben Funktions-, Test-, Release-,
  Installations-, Datenbank- und GitHub-Stand im `/quicken`-Thread 894. Sie
  erklärt ausdrücklich den wegen der gesperrten Sitzung fehlenden Screenshot.
  Exakter kumulativer Zielzählerstand nach Telegram- und PR-Prüfung:
  17.933.283 Tokens.

## 07.08.2026 – Freistellungsaufträge

- Der neue Arbeitsbereich `Freistellungsaufträge` verwaltet Steuerpersonen,
  Einzel- und gemeinsame Aufträge, Gültigkeitsjahre, Institute, institutionweit
  abgedeckte Konten sowie die jährliche Ausschöpfung. Aus Datenschutzgründen
  speichert er nur eine Bestätigung der Steuer-ID und optional deren letzte vier
  Stellen; er ersetzt weder das amtliche Formular noch eine Steuerberatung.
- Die Jahreslogik bildet die gesetzlichen Sparer-Pauschbeträge 801/1.602 EUR
  bis 2022 und 1.000/2.000 EUR ab 2023 ab. Sie verhindert Überbelegung,
  unzulässige Partnerkombinationen, institutsfremde Kontozuordnungen,
  Überschreitung der Auftragshöhe und nachträgliche Absenkung unter bereits
  genutzte Beträge. CSV, A4-PDF und Systemdruck beruhen auf demselben
  unveränderlichen Berichtssnapshot.
- SQLite-Schema 36 ergänzt Personen, Regeln, Aufträge, Kontodeckung und
  Jahresnutzung. Die Migration 35→36 bewahrt Bestandsdaten und legt vorab die
  bereits vorhandene wiederherstellbare Sicherung
  `FinanzVerwalter-vor-Migration-v35-20260807-152642-728-B42DC55D.qbackup` an.
- Der vollständige Testlauf ist grün: 136 Tests insgesamt, 135 bestanden,
  1 privater opt-in-QIF-Test planmäßig übersprungen, 0 fehlgeschlagen. Das
  Result-Bundle liegt unter
  `build/DerivedData-TaxAllowances/Logs/Test/Test-FinanzVerwalter-2026.08.07_17-17-26-+0200.xcresult`.
- Der optimierte arm64-Release unter
  `build/DerivedData-TaxAllowances-Release` wurde erfolgreich gebaut, lokal
  ad-hoc signiert und streng geprüft. `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich; die ausführbare Datei
  trägt SHA-256
  `ad3100ee0bb4c2c5d64f4b3a9f9fcce8e18aab1391abab53875c919dcfeb81b6`.
  Beide Vorgängerinstallationen liegen reversibel unter
  `build/InstallBackups/20260807-1726/`; Prozess 2575 läuft aus
  `/Applications`, und der Desktop-Link zeigt weiterhin dorthin.
- Die produktive Datei wurde mit Integrität `ok` als Schema 36 geöffnet und
  enthält unverändert 97 Konten, 2.170 Buchungen und 782 Kategorien. Die vier
  gesetzlichen Regeln sind vorhanden; Personen, Aufträge und Nutzungen bleiben
  bis zur bewussten Eingabe leer. Exakter kumulativer Zielzählerstand nach
  Test, Release, Installation und Produktivprüfung: 18.368.754 Tokens.
- Implementierung und Reproduktionsdokumentation wurden als Commit `e76d582`
  auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub Draft-PR #1
  nennt Schema 36, den 136-Test-Nachweis und den neuen Release-Hash; er ist
  offen und konfliktfrei mergebar.
- Telegram-Nachricht 1051 meldet denselben Stand im `/quicken`-Thread 894 und
  erklärt ausdrücklich den wegen der gesperrten Sitzung fehlenden Screenshot.
  Exakter kumulativer Zielzählerstand nach Veröffentlichung: 18.460.050 Tokens.

## 07.08.2026 – Reversibler Kreditratenabgleich und Plan/Ist-Bericht

- SQLite-Schema 37 erweitert Kreditratenzuordnungen um Sondertilgung,
  Herkunft sowie vollständige Transaktionszustände vor und nach dem Abgleich.
  Zwei Trigger verhindern, dass eine zugeordnete Kontobuchung über normale
  Bearbeitungs- oder Löschwege verändert wird. Die Migration rekonstruiert die
  historische, früher ungenutzte Tabelle defensiv, wenn eine frühe Altdatei sie
  nicht enthält.
- Offene Tilgungsplanzeilen bieten passende reale Belastungen des verknüpften
  Zahlungskontos innerhalb von ±45 Tagen an. Die Zuordnung zerlegt atomar in
  Tilgung, Sollzins, Gebühr und Mehrbetrag als Sondertilgung. Alternativ erzeugt
  `Planrate buchen` eine neue Splitbuchung. Beim Lösen wird diese entfernt oder
  eine vorhandene Buchung exakt auf den gespeicherten Originalzustand
  zurückgesetzt; Doppelzuordnung, Unterdeckung und Übertilgung werden
  abgewiesen.
- Der Kreditbericht zeigt nun Plan, Ist, Abweichung, Zuordnungsquelle und
  abgeglichene Raten in Oberfläche, CSV, mehrseitigem PDF und Systemdruck.
  Summen bleiben strikt je Währung getrennt. ADR 0029 beschreibt die
  Reversibilitätsentscheidung; README, Berichtswerkstatt, Anforderungsmatrix und
  `PortalPrompt.md` wurden reproduzierbar aktualisiert.
- Der vollständige Testlauf ist grün: 138 Tests insgesamt, 137 bestanden,
  1 privater opt-in-QIF-Test planmäßig übersprungen, 0 fehlgeschlagen. Das
  Result-Bundle liegt unter
  `build/DerivedData-LoanActual/Logs/Test/Test-FinanzVerwalter-2026.08.07_18-20-40-+0200.xcresult`.
- Der optimierte arm64-Release wurde unter
  `build/DerivedData-LoanActual-Release` erfolgreich gebaut, lokal ad-hoc
  signiert und streng geprüft. Release, `/Applications/FinanzVerwalter.app`
  und `~/Applications/FinanzVerwalter.app` sind bytegleich; die ausführbare
  Datei trägt SHA-256
  `c3f71e8c103cb3b9a03c7fea4c845eee171baa619634e58c97581811260c23a8`.
  Die Vorgängerinstallationen liegen reversibel unter
  `build/InstallBackups/20260807-1818-loan-matching/`, die manuelle geprüfte
  Schema-36-Sicherung unter
  `build/ProductionBackups/20260807-1818-loan-matching/`.
- Prozess 12666 läuft direkt aus `/Applications`; der Desktop-Link zeigt auf
  diese Installation. Die Produktionsdatei besitzt nach automatischer
  Vor-Migrationssicherung Schema 37 und Integrität `ok`; 97 Konten, 2.170
  Buchungen und 782 Kategorien blieben unverändert. Es existieren derzeit
  keine Darlehen und daher keine produktiven Kreditratenzuordnungen.
- Die Computer-Use-Prüfung konnte das Fenster wegen der gesperrten macOS-Sitzung
  nicht sichtbar abnehmen oder fotografieren. Die Sperre wurde nicht umgangen;
  nach manuellem Entsperren steht die bereits gestartete App bereit. Exakter
  kumulativer Zielzählerstand nach Test, Release, Installation und
  Produktivprüfung: 19.103.530 Tokens.
- Implementierung und Reproduktionsdokumentation wurden als Commit `f4850d8`
  auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub Draft-PR #1
  nennt Schema 37, den 138-Test-Nachweis und den finalen Release-Hash; er ist
  offen und nach der REST-Prüfung konfliktfrei mergebar.
- Telegram-Nachricht 1057 meldet denselben Stand im `/quicken`-Thread 894 und
  erklärt ausdrücklich den wegen der gesperrten Sitzung fehlenden Screenshot.
  Exakter kumulativer Zielzählerstand nach Veröffentlichung: 19.181.251 Tokens.

## 07.08.2026 – Decimal-Betragsrechner für manuelle Buchungen

- Der manuelle Buchungsdialog wertet in Hauptbetrag,
  Fremdwährungs-Originalbetrag, Splitzeilen und manuellen MwSt.-Beträgen nun
  `+`, `−`, `×`, `÷`, die Tastaturvarianten, Klammern, unäre Vorzeichen und ein
  optionales führendes `=` aus. Punktrechnung geht vor Strichrechnung;
  Split-Restbetrag, Fremdwährungskurs und MwSt. arbeiten anschließend mit den
  ausgewerteten Minor-Units.
- `MoneyExpressionParser` rechnet ohne `Double` ausschließlich mit `Decimal`,
  validiert deutsche Zahlentrenner vollständig und rundet erst das Endergebnis
  nach Währungspräzision. Division durch null, unvollständige Eingaben,
  Überlauf, mehr als 256 Zeichen, 32 Verschachtelungsebenen oder 128 Operationen
  werden ohne Teilbuchung abgewiesen. Dabei wurde auch der strikte
  Einzelwertparser gehärtet, weil Apples Decimal-Initialisierer `1..2` sonst
  stillschweigend als `1` akzeptiert.
- README, Anforderungsmatrix, `PortalPrompt.md` und ADR 0030 beschreiben
  Bedienung, Grenzen und eine vollständige Reproduktion ohne neue Abhängigkeit.
- Die gezielte Abnahme bestand mit 14/14 Parser-, Buchungs-, Split-,
  Fremdwährungs- und MwSt.-Tests. Der vollständige Testlauf ist grün: 145 Tests
  insgesamt, 144 bestanden, 1 privater opt-in-QIF-Test erwartungsgemäß
  übersprungen, 0 fehlgeschlagen. Das Result-Bundle liegt unter
  `build/TestResults/AmountCalculator-full-20260807-1856.xcresult`.
- Der optimierte arm64-Release unter
  `build/DerivedData-AmountCalculator-Release` wurde erfolgreich gebaut,
  ad-hoc signiert und streng geprüft. Release,
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` tragen für die ausführbare Datei
  SHA-256
  `6981888547bbc757f93911592631f934e71fbc4ee2502b147b84c44c5cbefd8f`.
  Die beiden Vorgängerinstallationen sind wiederherstellbar unter
  `build/InstallBackups/20260807-1900-amount-calculator/` gesichert; die
  validierte Datenbanksicherung liegt unter
  `build/ProductionBackups/20260807-1900-amount-calculator/`.
- Prozess 17324 läuft direkt aus `/Applications`; der Desktop-Link zeigt
  weiterhin dorthin. Die produktive Datei besitzt Schema 37 und Integrität
  `ok`; 97 Konten, 2.170 Buchungen und 782 Kategorien blieben unverändert.
- Die Computer-Use-Fertigkeit konnte das Fenster wegen der gesperrten
  macOS-Sitzung weiterhin nicht sichtbar abnehmen oder fotografieren. Die
  Sperre wurde nicht umgangen; die gestartete App steht nach manuellem
  Entsperren bereit. Exakter kumulativer Zielzählerstand nach Test, Release,
  Installation und Produktivprüfung: 19.473.734 Tokens.
- Implementierung und Reproduktionsdokumentation wurden als Commit `03e2b48`
  auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub Draft-PR #1
  nennt den 145-Test-Nachweis und den neuen Release-Hash; er ist offen und
  nach der REST-Prüfung konfliktfrei mergebar.
- Telegram-Nachricht 1059 meldet denselben Stand im `/quicken`-Thread 894 und
  erklärt ausdrücklich den wegen der gesperrten Sitzung fehlenden Screenshot.
  Exakter kumulativer Zielzählerstand nach Veröffentlichung: 19.492.107 Tokens.

## Direkter Serienentwurf aus einer Buchung, Schema 38 und Installation am 7. August 2026

- Das Kontoblatt bietet für genau eine ausgewählte Nicht-Umbuchung nun
  `Als regelmäßigen Vorgang …`. Der vorausgefüllte Monatsentwurf liegt heute
  oder künftig und bewahrt die Monatsende-Semantik. Eine einzelne Seite einer
  Umbuchung wird bewusst abgewiesen.
- Migration 38 ergänzt den vollständigen, deterministisch codierten
  Buchungsinhalt einer Serie. Notiz, Empfängerakte, Tags, Splits samt
  Split-Tags und MwSt. sowie Fremdwährungsbetrag und Kurs bleiben erhalten;
  Referenz-, Import-, Provider-, Bank-, Abgleichs- und Transferidentitäten
  werden nicht kopiert. Abweichende Beträge oder Kategorien einer Instanz
  entfernen abhängige Struktur statt inkonsistente Buchungen zu erzeugen.
- Der Serieneditor zeigt den geerbten strukturierten Inhalt an, beschränkt
  Kontowechsel auf offene Konten derselben Währung und schützt Betrag bzw.
  Kategorie, solange Splits, Steuer oder Fremdwährung davon abhängen. Der
  Store validiert Konto, Währung und vollständige Buchung erneut und speichert
  Payload und Audit atomar. ADR 0031 hält diese Invarianten fest.
- Die gezielten Modell-, Persistenz-, Serien- und Migrationstests sind grün.
  Der vollständige Lauf unter
  `build/TestResults/ScheduledFromBooking-full-20260807-1932.xcresult` umfasst
  147 Tests: 146 bestanden, 1 privater opt-in-Real-QIF-Test erwartungsgemäß
  übersprungen, 0 fehlgeschlagen.
- Der optimierte native arm64-Release unter
  `build/DerivedData-ScheduledFromBooking-Release` wurde gebaut, lokal ad-hoc
  signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `060872f77fc04a28654d5de6c3fe7b3771af8898a7cbe954f183ebbde9abe810`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Desktop-Link `FinanzVerwalter.app` zeigt auf die Systeminstallation.
- Beide Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-1936-scheduled-from-booking/`. Vor der
  Migration wurde die Produktivdatei als validiertes Schema-37-Backup unter
  `build/ProductionBackups/20260807-1936-scheduled-from-booking/` gesichert.
  Nach dem Start besitzt die Produktivdatei Schema 38 und Integrität `ok`;
  97 Konten, 2.170 Buchungen und 782 Kategorien blieben unverändert.
- Prozess 23802 läuft direkt aus `/Applications`. Die Computersteuerung konnte
  das Fenster wegen der gesperrten macOS-Sitzung nicht sichtbar prüfen oder
  fotografieren; die Sperre wurde nicht umgangen. Exakter kumulativer
  Zielzählerstand nach Test, Release, Installation und Produktivprüfung:
  19.853.136 Tokens.
- Implementierung und Reproduktionsdokumentation wurden als Commit `b75722a`
  auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub Draft-PR #1
  enthält Schema-38-, 147-Test-, Release- und Installationsnachweis und ist
  nach der GitHub-Prüfung konfliktfrei mergebar.
- Telegram-Nachricht 1064 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein neuer Screenshot
  behauptet. Exakter kumulativer Zielzählerstand der Nachricht:
  19.875.064 Tokens.

## Sichtmengengleicher Kontoblatt-CSV-Export am 7. August 2026

- Einzel- und Sammelkontoblatt exportieren im Menü `Ausgabe` nun exakt ihre
  sichtbaren Zeilen und Spalten als CSV. PDF, Systemdruck und CSV erhalten
  denselben unveränderlichen `RegisterPrintSnapshot`; vollständige Kategorie-
  und Klassenpfade, kontenweiser Saldo, Filter und sichtbare regelmäßige
  Zukunft werden nicht abweichend neu berechnet.
- Zur Wahl stehen Semikolon/UTF-8, Komma/UTF-8 und
  Semikolon/Windows-1252. CSV verwendet CRLF, verdoppelte Anführungszeichen
  und verlustfreie Maskierung von Trennzeichen und Zeilenumbrüchen. Ein im
  gewählten Encoding nicht darstellbares Zeichen bricht sichtbar ab, statt
  durch ein Ersatzzeichen Finanztexte zu verfälschen. ADR 0032 dokumentiert
  Snapshot- und Encoding-Entscheidung.
- Zwei bytegenaue Golden-File-Tests prüfen Wiederholbarkeit, sichtbare
  Spalten, vollständige Pfade, beide Trennzeichen, beide Encodings und den
  verlustfreien Fehlerfall. Der vollständige Lauf unter
  `build/TestResults/RegisterCSV-full-20260807-2000.xcresult` umfasst 149
  Tests: 148 bestanden, 1 privater opt-in-Real-QIF-Test erwartungsgemäß
  übersprungen, 0 fehlgeschlagen.
- Der optimierte native arm64-Release unter
  `build/DerivedData-RegisterCSV-Release` wurde gebaut, lokal ad-hoc signiert
  und streng geprüft. Die ausführbare Datei hat SHA-256
  `63d9dc9879b960d6a9e0eb4597574b5f49051a7a5cc6cdcd2b48ac19add103fe`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Desktop-Link zeigt weiterhin auf die Systeminstallation.
- Beide Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-1949-register-csv/`; die vor dem Austausch
  online validierte Produktivkopie unter
  `build/ProductionBackups/20260807-1949-register-csv/`. Nach dem Start
  besitzt die Produktivdatei weiterhin Schema 38 und Integrität `ok`; 97
  Konten, 2.170 Buchungen und 782 Kategorien blieben unverändert.
- Prozess 27542 läuft direkt aus `/Applications`. Die Computersteuerung kann
  das neue Ausgabemenü wegen der weiterhin gesperrten macOS-Sitzung nicht
  sichtbar prüfen oder fotografieren; die Sperre wurde nicht umgangen.
  Exakter kumulativer Zielzählerstand nach Test, Release, Installation und
  Produktivprüfung: 20.009.514 Tokens.
- Implementierung und Reproduktionsdokumentation wurden als Commit `111d49b`
  auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub Draft-PR #1
  enthält den 149-Test-, CSV-, Release- und Installationsnachweis und ist nach
  der GitHub-Prüfung konfliktfrei mergebar.
- Telegram-Nachricht 1066 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein neuer Screenshot
  behauptet. Exakter kumulativer Zielzählerstand der Nachricht:
  20.018.555 Tokens.

## Tastaturfreundliche Inline-Schnellbuchung am 7. August 2026

- Das Kontoblatt besitzt nun eine einblendbare `Schnellbuchung` direkt über
  der Tabelle. Die kompakte, horizontal scrollbare Zeile enthält Datum,
  ausschließlich offene Konten, Empfänger, Verwendungszweck, vollständigen
  Kategoriepfad, Status, Betrag und sichtbare Kontowährung.
- Der Betrag nutzt denselben begrenzten Decimal-Ausdrucksparser wie der
  vollständige Buchungsdialog. Eingabe im Betragsfeld speichert, Esc leert
  ohne Mutation und Tab bleibt normale Feldnavigation. Nach Erfolg bleiben
  Datum und Konto für Serienerfassung erhalten; die Inhaltsfelder werden
  geleert und der Fokus kehrt zum Empfänger zurück.
- `RegisterQuickEntryDraft` normalisiert Texte, prüft Konto und Betrag und
  erzeugt eine einfache manuelle Buchung mit Wertstellung gleich
  Buchungsdatum, ohne Transfer-/Importidentität und ohne Splits. Gespeichert
  wird über denselben atomaren Storepfad mit Audit und persistentem
  konfliktgeschütztem Undo. Komplexe Splits, Umbuchungen, MwSt.,
  Fremdwährung, Tags und Anhänge bleiben im vollständigen Dialog. ADR 0033
  dokumentiert diese Grenze.
- Die gezielte Abnahme prüft Parser, Persistenz, Status, Kategorie,
  geschlossene Konten, Parserfehler, Undo und das Durchlassen von
  Eingabe-/Texttasten. Der vollständige Lauf unter
  `build/TestResults/QuickEntry-full-20260807-2018.xcresult` umfasst 150
  Tests: 149 bestanden, 1 privater opt-in-Real-QIF-Test erwartungsgemäß
  übersprungen, 0 fehlgeschlagen.
- Der optimierte native arm64-Release unter
  `build/DerivedData-QuickEntry-Release` wurde gebaut, lokal ad-hoc signiert
  und streng geprüft. Die ausführbare Datei hat SHA-256
  `388df8e9349e8bb1477871faa899f149c93359e21eab2977bbf4013476c44f98`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Desktop-Link zeigt weiterhin auf die Systeminstallation.
- Beide Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-2002-quick-entry/`; die validierte
  Produktivkopie unter
  `build/ProductionBackups/20260807-2002-quick-entry/`. Nach dem Start besitzt
  die Produktivdatei weiterhin Schema 38 und Integrität `ok`; 97 Konten,
  2.170 Buchungen und 782 Kategorien blieben unverändert.
- Prozess 30594 läuft direkt aus `/Applications`. Die Computersteuerung kann
  die Schnellbuchungszeile wegen der weiterhin gesperrten macOS-Sitzung nicht
  sichtbar prüfen oder fotografieren; die Sperre wurde nicht umgangen.
  Exakter kumulativer Zielzählerstand nach Test, Release, Installation und
  Produktivprüfung: 20.106.054 Tokens.
- Implementierung und Reproduktionsdokumentation wurden als Commit `bac0b8a`
  auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub Draft-PR #1
  enthält den 150-Test-, Schnellbuchungs-, Release- und Installationsnachweis
  und ist nach der GitHub-Prüfung konfliktfrei mergebar.
- Telegram-Nachricht 1068 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein neuer Screenshot
  behauptet. Exakter kumulativer Zielzählerstand der Nachricht:
  20.112.344 Tokens.

## 07.08.2026 – stabile Kontoblatt-Sortierung bei chronologischem Saldo

- Das Einzelkontoblatt besitzt nun ein persistentes Menü `Sortierung` für
  auf- und absteigende Reihenfolge über alle elf Standardfelder: Datum,
  Wertstellung, Belegnummer, Status, Empfänger, Verwendungszweck,
  vollständiger Kategoriepfad, vollständige Klassen-/Tagpfade, Konto, Betrag
  und Saldo. Deutsche Texte werden case- und diakritikaunabhängig sowie
  natürlich numerisch mit `de_DE` verglichen. Gleichstände löst die Engine
  unabhängig von der Eingabereihenfolge über Buchungsdatum und UUID auf.
- Laufende Salden werden vor der sichtbaren Sortierung weiterhin fachlich
  chronologisch je Konto berechnet und bleiben als Eigenschaft ihrer Buchung
  erhalten. Eine Sortierung nach Kategorie, Betrag oder Saldo verfälscht
  deshalb keinen historischen Kontostand. CSV, PDF und Druck verwenden die
  bereits sortierte sichtbare Reihenfolge.
- Benannte Kontoblattansichten speichern Spalte und Richtung in zwei neuen
  optionalen Feldern. Alte JSON-Ansichten ohne diese Felder decodieren
  weiterhin und öffnen Datum aufsteigend. ADR 0034 dokumentiert Entscheidung,
  Folgen und die bewusst noch offene anklickbare Tabellenkopfsteuerung.
- Die gezielte Abnahme unter
  `build/TestResults/RegisterSort-final-targeted-20260807-2035.xcresult`
  bestand beide Sortier-/Kompatibilitätstests. Die vollständige Regression
  unter `build/TestResults/RegisterSort-full-20260807-2047.xcresult` umfasst
  151 Tests: 150 bestanden, 1 privater opt-in-Real-QIF-Test ohne temporären
  Pfad erwartungsgemäß übersprungen, 0 fehlgeschlagen und 0 erwartete Fehler.
- Der optimierte native arm64-Release unter
  `build/DerivedData-RegisterSort-Release` wurde erfolgreich gebaut, lokal
  ad-hoc signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `24d68f98e1e36f47abc57d6b59975f93666e7ece4017ef76e3f8d5a376419c19`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Desktop-Link zeigt weiterhin auf `/Applications/FinanzVerwalter.app`.
- Die Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-2016-register-sort/`. Eine mit SQLite
  konsistent erzeugte und danach geprüfte Produktionssicherung liegt unter
  `build/ProductionBackups/20260807-2016-register-sort/Meine Finanzen.qdata`.
- Nach dem Austausch läuft Prozess 33402 direkt aus `/Applications`. Die
  Produktivdatei und ihre Sicherung melden Integrität `ok`, Schema 38 und
  unverändert 97 Konten, 2.170 Buchungen sowie 782 Kategorien; die
  Produktivdatei enthält weiterhin 0 Serienbuchungen. Die private echte
  QIF-Datei wurde weder kopiert noch in Git aufgenommen.
- Die Computersteuerung konnte die installierte Oberfläche nicht sichtbar
  prüfen oder fotografieren, weil die macOS-Sitzung weiterhin gesperrt ist;
  die Sperre wurde nicht umgangen. Exakter kumulativer Zielzählerstand nach
  Test, Release, Installation und Produktivprüfung: 20.248.475 Tokens.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `3fe947f` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigt denselben Head, enthält den 151-Test- und
  Release-Nachweis und ist nach erneuter GitHub-Prüfung konfliktfrei
  mergebar.
- Telegram-Nachricht 1073 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein Screenshot behauptet.
  Exakter kumulativer Zielzählerstand der Nachricht: 20.270.407 Tokens;
  Zählerstand nach überprüfter Zustellung: 20.272.829 Tokens.

## 07.08.2026 – native anklickbare Sortierung in den Spaltenköpfen

- Jede dynamische Spalte des Einzelkontoblatts verwendet jetzt einen nativen
  SwiftUI-`TableColumn`-Komparator über `sortUsing`. Die Tabelle bindet ihr
  `sortOrder` an denselben persistenten Spalten-/Richtungszustand wie das
  Menü und die benannten Ansichten. Ein Klick auf einen anderen Kopf wählt
  ihn aufsteigend, der nächste Klick kehrt die Richtung um; macOS zeigt den
  Pfeil und stellt die systemeigene Tastatur-/Accessibility-Semantik bereit.
- `RegisterTableComparator` benutzt für alle elf Felder dieselben typisierten
  Werte, vollständigen Kategorie-/Klassenpfade, deutschen Textregeln,
  chronologischen Salden und stabilen Gleichstandsregeln wie
  `RegisterSorter`. Der native Tabellenkopfordner und die explizite Engine
  können dadurch nicht fachlich auseinanderlaufen.
- Der gezielte Lauf unter
  `build/TestResults/RegisterHeaderSort-final-targeted-20260807-2042.xcresult`
  prüft Zustandsübernahme sowie alle elf Spalten in beiden Richtungen. Die
  vollständige Regression unter
  `build/TestResults/RegisterHeaderSort-full-20260807-2045.xcresult` umfasst
  152 Tests: 151 bestanden, 1 privater opt-in-Real-QIF-Test ohne temporären
  Pfad erwartungsgemäß übersprungen, 0 fehlgeschlagen und 0 erwartete Fehler.
- Der optimierte native arm64-Release unter
  `build/DerivedData-RegisterHeaderSort-Release` wurde gebaut, lokal ad-hoc
  signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `f84a9444c7907af54dfef7542ef2046b1d96cff7311c151641697dc2a94baea2`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Desktop-Link zeigt weiterhin auf die Systeminstallation.
- Die Vorgängerinstallationen liegen unter
  `build/InstallBackups/20260807-2034-register-header-sort/`, die geprüfte
  SQLite-Sicherung unter
  `build/ProductionBackups/20260807-2034-register-header-sort/Meine Finanzen.qdata`.
  Nach dem Austausch läuft Prozess 35722 direkt aus `/Applications`.
  Produktivdatei und Sicherung melden Integrität `ok`, Schema 38 und
  unverändert 97 Konten, 2.170 Buchungen sowie 782 Kategorien.
- Die Computersteuerung bestätigt weiterhin eine gesperrte macOS-Sitzung und
  konnte den Tabellenkopfpfeil deshalb nicht sichtbar prüfen oder
  fotografieren; die Sperre wurde nicht umgangen. Exakter kumulativer
  Zielzählerstand nach Test, Release, Installation und Produktivprüfung:
  20.454.891 Tokens.
- Implementierung, Tests und Reproduktionsdokumentation wurden als Commit
  `2094dbb` auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub
  Draft-PR #1 zeigt denselben Head, enthält nun den 152-Test-, Tabellenkopf-,
  Release- und Installationsnachweis und ist konfliktfrei mergebar.
- Telegram-Nachricht 1077 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein Screenshot behauptet.
  Exakter Zielzählerstand der Nachricht: 20.467.184 Tokens; Zählerstand nach
  überprüfter Zustellung: 20.469.252 Tokens.

## 07.08.2026 – umschaltbare Betrag- oder Soll-/Haben-Spalten

- Einzel- und Sammelkontoblatt besitzen nun ein persistentes Menü für die
  fachlich alternative Darstellung `Betrag` oder `Soll / Haben`. Im
  getrennten Modus ersetzt das Paar die logische Betragsspalte an derselben
  Position; die unabhängige Spaltenkonfiguration speichert weiterhin nur
  `Betrag` und kann dadurch keine widersprüchliche Kombination erzeugen.
- Negative Buchungen erscheinen ohne Minuszeichen ausschließlich unter
  `Soll`, positive ausschließlich unter `Haben`, Null bleibt in beiden
  Spalten leer. `RegisterAmountPresentation` behandelt auch den kleinsten
  darstellbaren Ganzzahlwert ohne Überlauf. Der gespeicherte signierte Betrag
  wird weder migriert noch verändert.
- Einzel-, zweites und Sammelkontoblatt verwenden dieselbe Spaltenableitung.
  Native Kopf- und Menüsortierung, Accessibility-Zelltexte, benannte Einzel-
  und Sammelansichten sowie PDF, Systemdruck und CSV folgen derselben
  sichtbaren Spaltenfolge. Alte Ansichten ohne das neue optionale Feld öffnen
  rückwärtskompatibel mit der einzelnen Betragsspalte.
- Der gezielte Lauf unter
  `build/TestResults/DebitCredit-targeted-20260807-2100.xcresult` prüft
  insbesondere die verlustfreie Aufteilung, Layoutableitung, Ansichten-
  kompatibilität und Sortierung. Die vollständige Regression unter
  `build/TestResults/DebitCredit-full-20260807-2103.xcresult` umfasst 153
  Tests: 152 bestanden, 1 privater opt-in-Real-QIF-Test ohne temporären Pfad
  erwartungsgemäß übersprungen, 0 fehlgeschlagen und 0 erwartete Fehler.
- Der optimierte native arm64-Release unter
  `build/DerivedData-DebitCredit-Release` wurde erfolgreich gebaut, lokal
  ad-hoc signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `0b923cc5efed83bb980d4d2cd52e5fe72732cad50eec294724ad4e656a65e352`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Desktop-Link zeigt weiterhin auf `/Applications/FinanzVerwalter.app`.
- Die Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-2049-debit-credit/`. Eine mit SQLite
  konsistent erzeugte und danach geprüfte Produktionssicherung liegt unter
  `build/ProductionBackups/20260807-2049-debit-credit/Meine Finanzen.qdata`.
  Nach dem Austausch läuft Prozess 37052 direkt aus `/Applications`.
  Produktivdatei und Sicherung melden Integrität `ok`, Schema 38 und
  unverändert 97 Konten, 2.170 Buchungen sowie 782 Kategorien; die
  Produktivdatei enthält weiterhin 0 Serienbuchungen. Die private echte
  QIF-Datei wurde weder kopiert noch in Git aufgenommen.
- Die Computersteuerung bestätigte nach dem Start der neuen Installation
  erneut, dass die macOS-Sitzung gesperrt ist. Sie konnte deshalb weder den
  Umschalter noch die Spalten sichtbar prüfen oder fotografieren; die Sperre
  wurde nicht umgangen. Exakter kumulativer Zielzählerstand nach Build, Test,
  Installation, Produktivprüfung und diesem Prüfversuch: 20.622.297 Tokens.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `b940326` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigt denselben Head, enthält den 153-Test-, Soll-/Haben-,
  Release- und Installationsnachweis und ist konfliktfrei mergebar.
- Telegram-Nachricht 1082 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein Screenshot behauptet.
  Exakter Zielzählerstand der Nachricht: 20.645.964 Tokens; Zählerstand nach
  überprüfter Zustellung: 20.648.647 Tokens.

## 07.08.2026 – Saldoverlauf im Sammelkontoblatt

- Haupt- und zweite Sammelansicht zeigen jetzt oberhalb ihrer Tabellen einen
  währungsgetrennten Tagesverlauf. Ohne Filter beginnt jede Serie mit der
  Summe der Eröffnungssalden der eingeschlossenen offenen Konten, verarbeitet
  reale und erwartete Buchungen chronologisch und verdichtet auf den Wert
  nach der letzten wirksamen Buchung jedes Kalendertags. Stornos werden
  vollständig übersprungen.
- Sobald Konto-, Status-, Kategorie-, Klassen-/Tag-, Zeitraum- oder
  Volltextfilter die Grundgesamtheit einschränken, wechselt der Graph auf
  eine bei null beginnende kumulierte Bewegungssumme. Er schließt Stornos und
  beide Umbuchungsseiten aus und wird in Text, Farbe und Accessibility
  ausdrücklich `Gefilterte Bewegungssumme` statt Saldo genannt.
- Bei insgesamt weniger als 30 Tagespunkten sind die Punkte sichtbar. Hover
  ermittelt den zeitlich nächsten Tagespunkt, zeigt Datum und formatierten
  Währungsbetrag und markiert über die gespeicherte UUID die letzte wirksame
  Buchung dieses Tages in derselben Tabelle. EUR, USD und weitere Währungen
  besitzen unabhängige Serien und Skalen.
- `CombinedRegisterChartEngine` ist reine, deterministische Snapshot-Logik.
  Der gezielte Lauf unter
  `build/TestResults/CombinedChart-final-targeted-20260807-2102.xcresult`
  bestand. Die finale vollständige Regression unter
  `build/TestResults/CombinedChart-release-final-full-20260807-2108.xcresult`
  umfasst 154 Tests: 153 bestanden, 1 privater opt-in-Real-QIF-Test ohne
  temporären Pfad erwartungsgemäß übersprungen, 0 fehlgeschlagen und 0
  erwartete Fehler.
- Der optimierte native arm64-Release unter
  `build/DerivedData-CombinedChart-Release` wurde erfolgreich gebaut, lokal
  ad-hoc signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `7f10e90e3f8819f4b9e2870a39cebe5df2eeff3059ea296e0b9c796e8700416f`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Desktop-Link zeigt weiterhin auf `/Applications/FinanzVerwalter.app`.
- Die Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-2110-combined-chart-final/`. Die mit
  SQLite konsistent erzeugte und danach geprüfte Produktionssicherung liegt
  unter
  `build/ProductionBackups/20260807-2110-combined-chart-final/Meine Finanzen.qdata`.
  Nach dem Austausch läuft Prozess 39840 direkt aus `/Applications`.
  Produktivdatei und Sicherung melden Integrität `ok`, Schema 38 und
  unverändert 97 Konten, 2.170 Buchungen sowie 782 Kategorien; die
  Produktivdatei enthält weiterhin 0 Serienbuchungen. Die private echte
  QIF-Datei wurde weder kopiert noch in Git aufgenommen.
- Die Computersteuerung bestätigte nach dem Start der neuen Installation
  erneut die gesperrte macOS-Sitzung. Sie konnte den Graphen deshalb weder
  sichtbar bedienen noch fotografieren; die Sperre wurde nicht umgangen.
  Exakter kumulativer Zielzählerstand nach Umsetzung, Test, Release,
  Installation, Produktivprüfung und dem finalen Prüfversuch: 20.977.013 Tokens.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `4b61b80` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigt denselben Head, enthält den 154-Test-, Diagramm-,
  Release- und Installationsnachweis und ist konfliktfrei mergebar.
- Telegram-Nachricht 1087 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein Screenshot behauptet.
  Exakter Zielzählerstand der Nachricht: 20.987.656 Tokens; Zählerstand nach
  überprüfter Zustellung: 20.990.728 Tokens.

## 07.08.2026 – Einheitliche globale Kontenblatt-Volltextsuche

- `RegisterSearchIndex` bereitet beim Laden genau ein normalisiertes Dokument
  je persistenter Buchung vor. Es umfasst sämtliche Kontoangaben einschließlich
  Institut, Typ, Gruppe, IBAN/BIC, Kontonummer, Inhaber, Eröffnungsbetrag,
  Kreditlimit, Banksaldo und Syncstatus sowie Buchungstexte, vollständige
  Kategorie- und Klassenpfade aller Splits, Status, Datumswerte, Betrag,
  Netto, Steuer, laufenden Saldo, Fremdwährung und technische Bankreferenzen.
- Die Abfrage ist groß-/kleinschreibungs- und diakritikaunabhängig. Alle
  Suchwörter müssen vorkommen, dürfen aber aus verschiedenen Feldern stammen.
  Ein invertierter Index aus Ein-, Zwei- und Dreizeichenfragmenten erhält
  innere Wortteiltreffer wie `steuer` in `Grundsteuer`; eine anschließende
  Dokumentprüfung verhindert Fragment-Scheinmatches. Einzelkonto, zweites
  Kontenblatt sowie beide Sammelansichten verwenden dieselbe Logik.
- Der gezielte Regressionstest unter
  `build/TestResults/RegisterSearch-substring-targeted-20260807-2200.xcresult`
  deckt Kontofeld und Institut, vollständige Hierarchien, Status, Datum,
  formatierten Betrag, laufenden Saldo, IBAN, Bankreferenz, Diakritika,
  Mehrfeld- und Wortteilabfrage ab. Die Nutzerabfrage auf 100.000 bereits
  indexierten Dokumenten blieb unter der verbindlichen Grenze von 100 ms.
- Die finale vollständige Release-Regression unter
  `build/TestResults/RegisterSearch-substring-release-final-full-20260807-2205.xcresult`
  umfasst 155 Tests: 154 bestanden, 1 privater opt-in-Real-QIF-Test ohne
  temporären Pfad erwartungsgemäß übersprungen, 0 fehlgeschlagen und 0
  erwartete Fehler.
- Der optimierte native arm64-Release unter
  `build/DerivedData-FullText-Release` wurde erfolgreich gebaut, lokal ad-hoc
  signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `0ffb85dcd96f8c47bca3f2fd1cbf0fbcb5889f1ec6b3fc84ec6a3c3f7f5ec6af`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Schreibtisch-Link zeigt auf `/Applications/FinanzVerwalter.app`.
- Die Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-2145-fulltext-index/`. Die vor dem Austausch
  per SQLite konsistent erzeugte Produktionssicherung liegt unter
  `build/ProductionBackups/20260807-2145-fulltext-index/Meine Finanzen.qdata`.
  Nach dem Austausch läuft Prozess 44347 direkt aus `/Applications`.
  Produktivdatei und Sicherung melden Integrität `ok`, Schema 38 und
  unverändert 97 Konten, 2.170 Buchungen sowie 782 Kategorien; die
  Produktivdatei enthält weiterhin 0 Serienbuchungen. Die private echte
  QIF-Datei wurde weder kopiert noch in Git aufgenommen.
- Die Computersteuerung konnte die sichtbare Oberfläche nach dem Start nicht
  prüfen oder fotografieren, weil die macOS-Sitzung weiterhin gesperrt ist.
  Die Sperre wurde nicht umgangen. Exakter kumulativer Zielzählerstand nach
  Umsetzung, Test, Release, Installation, Produktivprüfung und diesem
  Prüfversuch: 21.322.286 Tokens.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `893a9b9` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigt denselben Head, nennt den 155-Test-, Volltext-,
  Release- und Installationsnachweis und ist konfliktfrei mergebar.
- Telegram-Nachricht 1094 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein Screenshot behauptet.
  Exakter Zielzählerstand der Nachricht: 21.366.330 Tokens; Zählerstand nach
  überprüfter Zustellung: 21.369.313 Tokens.

## 07.08.2026 – Überweisungsentwürfe korrigieren und abbrechen

- Ein freier Überweisungsentwurf besitzt nun die Aktionen
  `Entwurf bearbeiten …` und `Entwurf abbrechen …`. Der Editor übernimmt alle
  bisherigen Felder, korrigiert Konto, Zahlungsart, Empfängerakte,
  Bankverbindung, Betrag, Termin, Zweck, Zweckcode und End-to-End-ID und
  speichert erst nach erneuter vollständiger Prüfung.
- `updatePaymentOrderDraft` akzeptiert ausschließlich den Zustand `draft` und
  keinen Sammlerbestandteil. Es prüft innerhalb der SQLite-Mutation ein
  vorhandenes offenes EUR-Auftraggeberkonto, IBAN, optionale BIC,
  SEPA-Feldlängen sowie die exakte aktive Empfänger-/Bankverknüpfung. Der aus
  den kanonischen Feldern neu berechnete SHA-256-Idempotenzschlüssel darf mit
  keinem anderen Auftrag kollidieren. UUID, Erstellungszeit und Status bleiben
  erhalten; Version und `update_draft`-Audit steigen atomar.
- Abbrechen verlangt eine eigene Bestätigung, löscht keinen Datensatz und
  erzeugt keine Buchung. Der bereits vorhandene terminale Zustand `cancelled`
  ist jetzt aus freien Entwürfen und während `awaiting_user` erreichbar.
  Initialisierte, übermittelte, terminale und gebündelte Aufträge bleiben
  unveränderlich.
- Der gezielte Lauf unter
  `build/TestResults/PaymentDraftEdit-validation-targeted-20260807-2250.xcresult`
  bestand mit drei Zahlungs-/Stammdatentests. Die finale vollständige
  Release-Regression unter
  `build/TestResults/PaymentDraftEdit-release-full-20260807-2300.xcresult`
  umfasst 156 Tests: 155 bestanden, 1 privater opt-in-Real-QIF-Test ohne
  temporären Pfad erwartungsgemäß übersprungen, 0 fehlgeschlagen und 0
  erwartete Fehler.
- Der optimierte native arm64-Release unter
  `build/DerivedData-PaymentDraftEdit-Product` wurde erfolgreich gebaut,
  lokal ad-hoc signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `bb456b23900245f91f9668fd3d7b990520f8283d4d9f8f76efbbbad279bb78ed`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Schreibtisch-Link zeigt weiterhin auf `/Applications/FinanzVerwalter.app`.
- Die Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-2204-payment-draft-edit/`. Die vor dem
  Austausch per SQLite konsistent erzeugte Produktionssicherung liegt unter
  `build/ProductionBackups/20260807-2204-payment-draft-edit/Meine Finanzen.qdata`.
  Nach dem Austausch läuft Prozess 46931 direkt aus `/Applications`.
  Produktivdatei und Sicherung melden Integrität `ok`, Schema 38 und
  unverändert 97 Konten, 2.170 Buchungen sowie 782 Kategorien; beide enthalten
  0 Zahlungsaufträge. Die private echte QIF-Datei wurde weder kopiert noch in
  Git aufgenommen.
- Die Computersteuerung konnte den neuen Editor und die Abbruchbestätigung
  nicht sichtbar bedienen oder fotografieren, weil die macOS-Sitzung weiterhin
  gesperrt ist. Die Sperre wurde nicht umgangen. Exakter kumulativer
  Zielzählerstand nach Umsetzung, Test, Release, Installation,
  Produktivprüfung und diesem Prüfversuch: 21.552.061 Tokens.
- Nach den abschließenden direkten Grenzwertprüfungen für EUR, BIC und
  End-to-End-ID bestand auch der fokussierte Lauf unter
  `build/TestResults/PaymentDraftEdit-final-targeted-20260807-2310.xcresult`
  mit 1 Test, 1 bestanden, 0 übersprungen und 0 Fehlern.
- Implementierung, Test und Dokumentation wurden als Commit `93611cd` auf
  `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub Draft-PR #1 zeigt
  denselben Head, enthält den aktualisierten Zahlungs-, Release- und
  Installationsnachweis und wurde danach als mergebar bestätigt.
- Telegram-Nachricht 1097 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein Screenshot behauptet.
  Exakter Zielzählerstand der Nachricht: 21.617.845 Tokens.

## 08.08.2026 – Einheitlicher Abbruch für Lastschriften und SEPA-Sammler

- Einzelne, nicht gebündelte SEPA-Core-Lastschriften besitzen in `draft` und
  `awaiting_user` jetzt eine eigene bestätigungspflichtige Abbruchaktion. Sie
  löscht nichts, verändert den eingefrorenen Konto-/Zahler-/Mandatsschnappschuss
  nicht und erzeugt keine Buchung. Der terminale Auftrag kann nicht erneut
  eingereicht werden.
- Überweisungs- und Lastschriftsammler besitzen dieselbe sichtbare Aktion. Das
  vorhandene Repository bewegt Sammler und sämtliche geordneten Mitglieder
  atomar nach `cancelled`; ein abweichender Mitgliedsstatus verwirft den ganzen
  Vorgang. Es entstehen weder Einzel- noch Teilbuchungen.
- Lastschriftentwürfe werden beim Speichern zusätzlich gegen Namen und Zweck
  bis 140 Zeichen, End-to-End-ID und Mandatsreferenz bis 35 Zeichen, beide
  optionale BICs und die SEPA-Slashregeln geprüft. Die Prüfung liegt bewusst
  im Persistenz-Gate, sodass der bestehende `pain.008`-Exporter weiterhin seine
  präzisen typisierten Exportfehler liefert.
- Der gezielte Release-Lauf unter
  `build/TestResults/PaymentCancellation-targeted3-20260807-2350.xcresult`
  bestand mit 3 von 3 Tests. Er deckt Lastschriftanlage und -abbruch,
  atomaren Sammlerabbruch ohne Buchung sowie den unveränderten pain.008-
  Fehlervertrag ab.
- Die finale vollständige Release-Regression unter
  `build/TestResults/PaymentCancellation-release-full-final-20260807-2358.xcresult`
  umfasst 156 Tests: 155 bestanden, 1 privater opt-in-Real-QIF-Test ohne
  temporären Pfad erwartungsgemäß übersprungen, 0 fehlgeschlagen und 0
  erwartete Fehler.
- Der optimierte native arm64-Release unter
  `build/DerivedData-PaymentCancellation-Product` wurde erfolgreich gebaut,
  lokal ad-hoc signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `332f7de344b7f6c9bc8f602a2e2563f915d16e8db2eb788fac9c840e5a735ad7`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Schreibtisch-Link zeigt auf `/Applications/FinanzVerwalter.app`.
- Die Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260808-0004-payment-cancellation/`. Die per SQLite
  konsistent erzeugte Produktionssicherung liegt unter
  `build/ProductionBackups/20260808-0004-payment-cancellation/Meine Finanzen.qdata`.
  Nach dem Austausch läuft Prozess 50339 direkt aus `/Applications`.
  Produktivdatei und Sicherung melden Integrität `ok`, Schema 38 und
  unverändert 97 Konten, 2.170 Buchungen sowie 782 Kategorien; die
  Produktivdatei enthält 0 Überweisungen, Lastschriften und Sammler. Die
  private echte QIF-Datei wurde weder kopiert noch in Git aufgenommen.
- Die Computersteuerung konnte die neue Oberfläche nicht sichtbar bedienen
  oder fotografieren, weil die macOS-Sitzung weiterhin gesperrt ist. Die
  Sperre wurde nicht umgangen. Exakter kumulativer Zielzählerstand nach
  Umsetzung, Regression, Release, Installation, Produktivprüfung und diesem
  Prüfversuch: 21.848.037 Tokens.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `4a81357` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigte danach denselben Head, enthielt den aktualisierten
  Abbruch-, Release- und Installationsnachweis und war mergebar.
- Telegram-Nachricht 1101 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein Screenshot behauptet.
  Exakter Zielzählerstand der Nachricht: 21.861.107 Tokens.

## 08.08.2026 – Reproduzierbarer Kontenblatt-Referenzdatensatz und 100.000er Leistungstest

- Die Startoption `-reference-demo` erzeugt unabhängig von privaten Dateien
  eine temporäre Finanzdatei mit 12 stabilen Konten in vier Gruppen, drei
  Währungen, 10.000 Buchungen über zehn Jahre, 200 Splitzeilen und 150
  ausgeglichenen Umbuchungen. Ein Manifest hält Struktur, Datumsgrenzen und
  erwartete Berichtssummen fest.
- Der SQLite-Stapelpfad validiert zuerst vollständig und schreibt danach mit
  wiederverwendeten Prepared Statements atomar. Der Buchungsleser lädt
  Splits sowie Buchungs- und Split-Tags gebündelt und beseitigt das frühere
  N+1-Abfragemuster.
- Der feste Datenbanktag `yyyy-MM-dd` wird jetzt mit gültigem Schaltjahr und
  Monatstag direkt dekodiert. Dadurch fiel der vollständige Startkern bei
  100.000 Buchungen von 6,018 auf 0,994 Sekunden.
- Ab 25.001 Buchungen entsteht der globale Volltextindex verzögert auf einer
  Utility-Task; ein Generationswert schützt vor der Übernahme veralteter
  Ergebnisse. Vor Fertigstellung bleibt die direkte Suchprüfung korrekt.
- Der explizite 100.000er Debug-Lauf unter
  `build/TestResults/ReferenceRegister-100k-final-20260807-231329.xcresult`
  bestand mit 90.000 Zusatzbuchungen in 2,233 s, Start in 0,994 s,
  Kontenblatt in 0,389 s und Standardbericht in 1,982 s. Alle vier
  Mastergrenzen wurden damit eingehalten.
- Die abschließende vollständige Regression unter
  `build/TestResults/Full-reference-20260807-231427.xcresult` umfasst 158
  Tests: 156 bestanden, 2 explizite opt-in-Tests übersprungen, 0 Fehler und 0
  erwartete Fehler. Einer der übersprungenen Tests ist der private QIF-Lauf,
  der andere der bereits separat bestandene 100.000er Lauf.
- Die private echte QIF-Datei wurde weder gelesen noch kopiert oder in Git
  aufgenommen. Die sichtbare UI-Prüfung bleibt wegen der gesperrten macOS-
  Sitzung ungeprüft; die Sperre wird nicht umgangen.
- Der native arm64-Release unter `build/DerivedData-Reference-Product` wurde
  erfolgreich gebaut und lokal ad-hoc signiert. Die ausführbare Datei hat
  SHA-256
  `8423d4a5cae95334de4989dec861c42a85352df27a84904bd8cfa95567378671`.
  Die strenge lokale `codesign`-Prüfung besteht; die Gatekeeper-Bewertung
  lehnt das Paket erwartungsgemäß ab, weil noch keine Developer-ID-
  Signierung und Apple-Notarisierung vorliegen.
- Die Vorgängerinstallationen liegen wiederherstellbar unter
  `build/InstallBackups/20260807-2320-reference-performance/`. Die konsistente
  Produktionssicherung liegt unter
  `build/ProductionBackups/20260807-2320-reference-performance/Meine Finanzen.qdata`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich installiert; der
  Schreibtisch-Link zeigt auf die erste Installation. Prozess 55638 läuft
  daraus. Produktivdatei und Sicherung melden Integrität `ok`, Schema 38 und
  unverändert 97 Konten, 2.170 Buchungen, 782 Kategorien sowie 0
  Überweisungen, Lastschriften und Sammler.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `d6d82e0` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigte denselben Head und war mergebar.
- Telegram-Nachricht 1109 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der gesperrten Sitzung wurde transparent kein Screenshot behauptet.
  Exakter Zielzählerstand der Nachricht: 22.284.553 Tokens.

## 08.08.2026 – Vollständige Kontostammdaten in Schema 39

- Schema 39 ergänzt jedes Konto additiv um Kontountertyp, deutsche BLZ,
  separaten Stichtag des Eröffnungssaldos, Schließdatum und ein optionales
  zugeordnetes Verrechnungs-/Anlage-/Darlehens-/Gegenkonto. Die
  Selbst-Fremdschlüsselbeziehung setzt sich bei einer späteren Kontolöschung
  auf `NULL` und besitzt einen Index.
- Die Persistenz akzeptiert nur leere oder achtstellige numerische BLZ,
  begrenzt den Untertyp auf 80 UTF-8-Bytes ohne Steuerzeichen, schützt vor
  Selbst- und Phantomverknüpfung und validiert die chronologische Reihenfolge
  von Eröffnung, Saldo-Stichtag und Schließung.
- Der erste Produktivstart traf unmittelbar nach dem Beenden der alten App
  noch auf deren auslaufende SQLite-Verbindung und brach die Migration ohne
  Teilwirkung ab. Ein sauberer Neustart migrierte vollständig. Daraufhin wurde
  für jede Verbindung ein Busy-Timeout von fünf Sekunden ergänzt, damit ein
  solches kurzes Freigabefenster künftig automatisch überbrückt wird.
- Der Kontoeditor bietet alle fünf Felder. Die Kontenübersicht zeigt den
  Untertyp; direktes Schließen setzt den heutigen Tag, Wiederöffnen entfernt
  ihn. Untertyp, BLZ und beide neuen Datumsfelder sind global durchsuchbar.
- Der gezielte Lauf unter
  `build/TestResults/AccountMasterData-targeted-20260807-233017.xcresult`
  bestand mit 3 von 3 Tests. Migration 38→39, vollständiger Rundlauf,
  Suche, Schutzregeln, Zukunftsschema und Integrität sind abgedeckt.
- Die vollständige Regression unter
  `build/TestResults/AccountMasterData-full-20260807-233114.xcresult`
  umfasst 160 Tests: 158 bestanden, 2 opt-in-Läufe übersprungen, 0 Fehler und
  0 erwartete Fehler.
- Nach Ergänzung des fünfsekündigen SQLite-Busy-Timeouts bestand die finale
  vollständige Regression unter
  `build/TestResults/AccountMasterData-busytimeout-full-20260807-233750.xcresult`
  erneut mit 160 Tests: 158 bestanden, 2 opt-in-Läufe übersprungen, 0 Fehler
  und 0 erwartete Fehler.
- Der finale native arm64-Release unter
  `build/DerivedData-AccountMasterData-Product` wurde erfolgreich gebaut,
  lokal ad-hoc signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `96381a8706f3cb99f9b7e01880d75cf56cfd115f662998bdb326dc82434c7cc9`.
- Die unmittelbar vorherige Installation liegt wiederherstellbar unter
  `build/InstallBackups/20260807-2342-account-masterdata-final/`; die
  konsistente Schema-39-Sicherung liegt unter
  `build/ProductionBackups/20260807-2342-account-masterdata-final/Meine Finanzen.qdata`.
  Beide installierten Apps sind bytegleich, der Schreibtisch-Link zeigt auf
  `/Applications`, und Prozess 57847 läuft aus dieser Installation.
  Produktivdatei und Sicherung melden Integrität `ok`; die Produktivdatei hat
  keine Fremdschlüsselverletzung, Schema 39, alle fünf neuen Kontospalten und
  unverändert 97 Konten, 2.170 Buchungen, 782 Kategorien sowie 0
  Überweisungen, Lastschriften und Sammler.
- Implementierung, Migration, Tests, ADR und Dokumentation wurden als Commit
  `891b003` veröffentlicht. GitHub Draft-PR #1 zeigte denselben Head und war
  mergebar.
- Telegram-Nachricht 1113 meldet den Stand im `/quicken`-Thread 894. Wegen der
  weiterhin gesperrten macOS-Sitzung wurde transparent kein Screenshot
  behauptet. Exakter Zielzählerstand der Nachricht: 22.435.371 Tokens.

## 08.08.2026 – Mehrere strikt getrennte Finanzdateien

- Das Ablage-Menü kann mit `⇧⌘N` eine neue `.qdata`-Finanzdatei erzeugen, mit
  `⌘O` eine vorhandene öffnen und höchstens zehn zuletzt verwendete Dateien
  anbieten. Die letzte erfolgreiche Auswahl wird beim nächsten normalen Start
  wiederverwendet; Demo- und Teststarts verändern diese Präferenz nicht.
- Jeder Wechsel erzeugt vorher auch bei abgeschalteter regulärer
  Autosicherung zwingend ein geprüftes SQLite-Online-Backup. Danach werden
  Kontoauswahl und Suche verworfen, der neue Bestand vollständig geladen,
  offene Editoren geschlossen und erst anschließend die alte Verbindung
  geschlossen. Schlägt der Kandidat fehl, bleibt die vorige Finanzdatei mit
  ihren Daten aktiv.
- Öffnen akzeptiert nur reguläre, direkte `.qdata`-Dateien. Neuanlegen
  verweigert vorhandene Ziele, symbolische Elternordner, falsche Endungen und
  leere, überlange oder steuerzeichenhaltige Namen. Die MRU-Liste blendet
  fehlende Dateien und Symlinks aus. Der Statusbereich zeigt den Dateinamen
  und als Hilfetext den vollständigen Pfad.
- Die gezielten Mehrdateitests unter
  `build/TestResults/MultiFile-targeted-20260807-2352.xcresult` bestanden mit
  2 von 2 Tests. Sie prüfen echte getrennte SQLite-Dateien, Wechsel in beide
  Richtungen, Dateikopf, Sicherungen, MRU-Reihenfolge sowie Fehler-Rollback.
- Die finale vollständige Regression unter
  `build/TestResults/MultiFile-final-full-20260807-2359.xcresult` umfasst 162
  Tests: 160 bestanden, 2 ausdrücklich opt-in übersprungen, 0 Fehler und 0
  erwartete Fehler.
- Der finale native arm64-Release unter
  `build/DerivedData-MultiFile-Product` wurde erfolgreich gebaut, lokal
  ad-hoc signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `d228e101d306a6ec701a2f0796f0dd058686e5577b222774d271508ffe13f0ce`.
- Die unmittelbar vorherige Installation liegt wiederherstellbar unter
  `build/InstallBackups/20260808-0002-pre-final-hardening/`; die konsistente
  Produktivsicherung liegt unter
  `build/ProductionBackups/20260808-0002-pre-final-hardening/Meine Finanzen.qdata`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich, der Schreibtisch-Link
  zeigt auf `/Applications`, und Prozess 59976 läuft daraus. Die zuletzt
  verwendete Datei ist die vorhandene Standarddatei. Produktivdatei und
  Sicherung melden Integrität `ok`, Schema 39 und unverändert 97 Konten,
  2.170 Buchungen, 782 Kategorien sowie 0 Überweisungen, Lastschriften und
  Sammler.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `9f02b9c` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigte denselben Head und war mergebar.
- Telegram-Nachricht 1117 meldet denselben Stand im `/quicken`-Thread 894.
  Wegen der weiterhin gesperrten macOS-Sitzung wurde transparent kein
  Screenshot behauptet. Exakter kumulativer Zielzählerstand vor dem Versand:
  22.712.877 Tokens.

## 08.08.2026 – Schließen, atomare Kopie und Archivsnapshot

- Das Ablage-Menü kann die aktive Finanzdatei nach Bestätigung schließen,
  eine unabhängige `.qdata`-Arbeitskopie oder einen schreibgeschützten
  `.qarchive`-Archivstand erzeugen. Schließen erzwingt vorab eine validierte
  Online-Sicherung und leert danach Finanzdaten, Auswahl, Suche und den
  Buchungsindex; Öffnen und Neuanlegen funktionieren ohne Neustart weiter.
- Kopie und Archiv entstehen per SQLite Online Backup zunächst unter einem
  zufälligen versteckten Namen im direkten Zielordner. Vor und nach der
  atomaren Verschiebung werden Integrität, Größe und SHA-256 geprüft.
  Vorhandene Ziele, die aktive Datei, falsche Endungen und symbolische
  Zielordner werden abgewiesen. Kopien erhalten Modus 0600, Archive Modus
  0400; der Status zeigt den Dateinamen und einen SHA-256-Kurzabdruck.
- Der Archivtest verändert nach dem Snapshot den Arbeitsbestand, stellt dann
  das Archiv über den normalen validierenden Restore-Pfad wieder her und
  prüft Bestand, aktive Zieldatei und Integrität. Der finale vollständige Lauf
  unter `build/TestResults/FileLifecycle-full-final-20260808-0013.xcresult`
  umfasst 164 Tests: 162 bestanden, 2 ausdrücklich opt-in übersprungen,
  0 Fehler und 0 erwartete Fehler.
- Der native arm64-Release unter
  `build/DerivedData-FileLifecycle-Product` wurde erfolgreich gebaut, lokal
  ad-hoc signiert und streng geprüft. Die ausführbare Datei hat SHA-256
  `0f645d58ef5c4af9854f6d8244d54fa600b1b34a799a4d6f04ddc48b86930063`.
- Die vorherigen Installationen liegen wiederherstellbar unter
  `build/InstallBackups/20260808-0018-file-lifecycle/`; die konsistente
  Produktivsicherung liegt unter
  `build/ProductionBackups/20260808-0018-file-lifecycle/Meine Finanzen.qdata`.
  `/Applications/FinanzVerwalter.app` und
  `~/Applications/FinanzVerwalter.app` sind bytegleich, der Schreibtisch-Link
  zeigt auf `/Applications`, und Prozess 61743 läuft daraus. Die
  Produktivdatei meldet Integrität `ok`, keine Fremdschlüsselverletzung,
  Schema 39 und unverändert 97 Konten, 2.170 Buchungen und 782 Kategorien.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `32dcff4` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigte denselben Head und war mergebar.
- Telegram-Nachricht 1121 meldet den geprüften Stand im `/quicken`-Thread
  894. Wegen der weiterhin gesperrten macOS-Sitzung wurde transparent kein
  neuer Screenshot behauptet. Exakter kumulativer Zielzählerstand vor dem
  Versand: 22.946.692 Tokens.

## 08.08.2026 – Read-only Wiederherstellungsvorschau

- Der Sicherungsdialog kopiert die ausgewählte Datei in eine private
  0600-Tempdatei und liest sie ausschließlich read-only mit SQLite
  `immutable=1`. Die modale Vorschau zeigt Quelldatei, Finanzdateiname,
  Basiswährung, Schema, Konten-, Kategorien- und Buchungszahl, jüngste
  Buchung, Dateigröße und Dateistand. Abbruch, Fehler und Abschluss entfernen
  die Tempdatei.
- Ein intaktes, aber neueres Schema wird vor Sicherheitskopie, Schließen oder
  Austausch mit verständlicher Versionsmeldung abgewiesen. Die Vorschau
  erzeugt weder WAL noch SHM und verändert den SHA-256 der Sicherung nicht.
  Der eigentliche Restore validiert Quelle, Sicherheitskopie und interne
  Staging-Datei erneut, verwendet kollisionsfreie Namen und rollt bei einem
  nachgelagerten Öffnungsfehler auf die geprüfte Sicherheitskopie zurück.
- Die gezielten Vorschautests unter
  `build/TestResults/RestorePreview-targeted-20260808-0027.xcresult` bestanden
  mit 4 von 4 Tests. Der finale vollständige Lauf unter
  `build/TestResults/RestorePreview-full-final-20260808-0032.xcresult`
  umfasst 166 Tests: 164 bestanden, 2 ausdrücklich opt-in übersprungen,
  0 Fehler und 0 erwartete Fehler.
- Der native arm64-Release unter `build/DerivedData-RestorePreview-Product`
  wurde erfolgreich gebaut, lokal ad-hoc signiert und streng geprüft. Die
  ausführbare Datei hat SHA-256
  `2857850347be3df8ba0bfac563f41b777a1a6ff230383a7fb00eceda4d356ace`.
- Die vorherigen Installationen liegen wiederherstellbar unter
  `build/InstallBackups/20260808-0035-restore-preview/`; die konsistente
  Produktivsicherung liegt unter
  `build/ProductionBackups/20260808-0035-restore-preview/Meine Finanzen.qdata`.
  Beide installierten Apps sind bytegleich, der Schreibtisch-Link zeigt auf
  `/Applications`, und Prozess 63669 läuft daraus. Die Produktivdatei meldet
  Integrität `ok`, keine Fremdschlüsselverletzung, Schema 39 und unverändert
  97 Konten, 2.170 Buchungen und 782 Kategorien.
- Implementierung, Tests, ADR und Reproduktionsdokumentation wurden als
  Commit `f87b392` auf `origin/agent/qif-mehrkontenimport` veröffentlicht.
  GitHub Draft-PR #1 zeigte denselben Head und war sauber mergebar.
- Telegram-Nachricht 1125 meldet den geprüften Stand im `/quicken`-Thread
  894. Wegen der weiterhin gesperrten macOS-Sitzung wurde transparent kein
  neuer Screenshot behauptet. Exakter kumulativer Zielzählerstand vor dem
  Versand: 23.121.029 Tokens.

## 08.08.2026 – Pfadbasierte Kategoriehierarchiesuche

- Die Kategorieverwaltung durchsucht Name, vollständigen Pfad, Beschreibung,
  Kategorieart sowie deutsche und US-Steuerzuordnung. Mehrere Suchwörter
  werden als UND-Bedingung ausgewertet; Groß-/Kleinschreibung, Diakritika und
  Zeichenbreite werden ignoriert. Alle Ahnen eines Treffers bleiben sichtbar,
  damit tiefe Kategoriepfade im Baum nicht auseinanderfallen.
- `Inaktive anzeigen` filtert inaktive Treffer. Eine inaktive Oberkategorie
  bleibt als notwendiger Pfad sichtbar, wenn eine aktive Unterkategorie passt.
  Während einer Suche zeigt jede Trefferzeile den vollständigen Pfad kompakt
  in einer zweiten Zeile und ungekürzt im Hilfetext. Eine leere Treffermenge
  besitzt einen erklärenden Leerzustand.
- ADR 0045 dokumentiert die Entscheidung. Der neue reine Logiktest deckt tiefe
  Immobilienpfade, Mehrwortsuche, `Köln`/`koln`, `Rücklage`/`rucklage`,
  Beschreibung, Steuerzeile, inaktive Blätter und inaktive Ahnen ab.
- Der finale vollständige Lauf unter
  `build/TestResults/CategorySearch-full-final-20260808-0050.xcresult`
  umfasst 167 Tests: 165 bestanden, 2 ausdrücklich opt-in übersprungen,
  0 Fehler und 0 erwartete Fehler.
- Der native arm64-Release unter `build/DerivedData-CategorySearch-Product`
  wurde erfolgreich gebaut, lokal ad-hoc signiert und streng geprüft. Die
  ausführbare Datei hat SHA-256
  `1be3a0b7254c1e780d5561a22ab67d0c43f24cab6d174f59fc8f8f53edceadfb`.
- Die vorherigen Installationen liegen wiederherstellbar unter
  `build/InstallBackups/20260808-0048-category-search/`; die konsistente
  Produktivsicherung liegt unter
  `build/ProductionBackups/20260808-0048-category-search/Meine Finanzen.qdata`.
  Beide installierten Apps sind bytegleich, der Schreibtisch-Link zeigt auf
  `/Applications`, Finder wurde auf die App gelenkt und Prozess 65253 läuft
  daraus. Produktivdatei und Sicherung melden Integrität `ok`, Schema 39 und
  jeweils 97 Konten, 2.170 Buchungen und 782 Kategorien; die Produktivdatei
  hat keine Fremdschlüsselverletzung.
- Implementierung, Test, ADR und Reproduktionsdokumentation wurden als Commit
  `306209a` auf `origin/agent/qif-mehrkontenimport` veröffentlicht. GitHub
  Draft-PR #1 zeigte denselben Head und war mergebar.
- Telegram-Nachricht 1129 meldet den geprüften Stand im `/quicken`-Thread
  894. Wegen der weiterhin nicht sichtbar entsperrten macOS-Sitzung wurde
  transparent kein neuer Screenshot behauptet. Exakter kumulativer
  Zielzählerstand vor dem Versand: 23.293.152 Tokens.

## 08.08.2026 – Versionierter CSV-/TSV-Profilassistent

- Vor der normalen Importvorschau öffnet sich ein eigener Assistent mit
  automatischer und vollständig überschreibbarer Erkennung für UTF-8,
  Windows-1252/ISO-Latin-1, Semikolon/Komma/Tab, Kopfzeile, vier Datumsformate,
  Dezimal-/Tausenderzeichen sowie Betrag oder getrennte Soll-/Haben-Spalten.
  Die ersten 20 Datenzeilen bleiben als Rohdaten sichtbar.
- Sämtliche fachlichen Quellspalten lassen sich frei zuordnen. Der neue Parser
  verarbeitet CRLF, maskierte Trennzeichen, verdoppelte Anführungszeichen und
  mehrzeilige Felder. Er liest Geld ohne Binärgleitkomma, setzt Soll negativ
  und Haben positiv und meldet Struktur-, Datums-, Betrags- und
  Soll/Haben-Fehler mit echter Quellzeilennummer.
- Neben Empfänger, Zweck, Notiz und Referenz werden Valuta, externe ID,
  Provider, IBAN/BIC, End-to-End-ID, Mandatsreferenz, Gläubiger-ID,
  Buchungstext und Banksaldo übernommen. Kategorien werden über vollständige
  Pfade oder nur bei eindeutigem Blattnamen aufgelöst. Unbekannte und
  mehrdeutige Kategorien werden niemals still verworfen.
- Benannte Profile werden ohne Buchungsdaten als schema-versioniertes JSON in
  `UserDefaults` gespeichert. Erneutes Speichern erhöht die Revision; ein
  unbekanntes Zukunftsschema wird abgewiesen. Nach der Profilierung bleibt das
  vorhandene gestufte Matching mit Datumsfenster und atomarem Commit erhalten.
- Vier gezielte Tests bestanden ohne Fehler. Der vollständige Lauf unter
  `build/TestResults/CSVProfile-full-20260808-0111.xcresult` umfasst 171 Tests:
  169 bestanden, 2 ausdrücklich opt-in übersprungen, 0 Fehler und 0 erwartete
  Fehler.
- Der native arm64-Release unter `build/DerivedData-CSVProfile-Product` wurde
  erfolgreich gebaut, ad-hoc signiert und streng geprüft. Die ausführbare
  Datei hat SHA-256
  `2161068a384bded5cf588dac9ab2d33cfd50bb3cfeac5a9cc2efe9e2033ea6a2`.
- Die vorherigen Installationen liegen wiederherstellbar unter
  `build/InstallBackups/20260808-0117-csv-profile/`; die konsistente
  Produktivsicherung liegt unter
  `build/ProductionBackups/20260808-0117-csv-profile/Meine Finanzen.qdata`.
  `/Applications/FinanzVerwalter.app` und `~/Applications/FinanzVerwalter.app`
  sind bytegleich, der Schreibtisch-Link zeigt auf `/Applications`, und
  Prozess 68881 läuft daraus. Produktivdatei und Sicherung melden Integrität
  `ok`, Schema 39 und jeweils unverändert 97 Konten, 2.170 Buchungen und 782
  Kategorien; die Produktivdatei hat keine Fremdschlüsselverletzung.
- Finder wurde auf die Systeminstallation gelenkt. Eine sichtbare
  Oberflächenabnahme und ein neuer Screenshot waren nicht möglich, weil die
  macOS-Sitzung weiterhin gesperrt ist; die laufende App wurde nicht fälschlich
  als sichtbar geprüft dokumentiert.
