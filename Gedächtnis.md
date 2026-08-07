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
