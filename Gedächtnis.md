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
