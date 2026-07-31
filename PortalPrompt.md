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

Migrationen 1 bis 10, Konto-/Kategorie-/Buchungspersistenz, Splits, atomare
Transfers, QIF/CSV, Kontoabgleich, Sammelkontoblatt, Bericht, Backup,
validierte Wiederherstellung, Kategorisierungsregeln und ein erster
Serientermin-/Prognose-Slice sowie monatliche Kategorie-Budgets sind
implementiert. Zusätzlich ist ein rein lokaler Banking-Simulator mit
Zahlungsaufträgen und SCA-Zustandsautomat vorhanden. Die Testsuite umfasst
aktuell achtzehn erfolgreiche
XCTest-Fälle. Debug- und Release-Build wurden
erfolgreich ausgeführt; der Release-Stand ist lokal installiert und sichtbar
geprüft. Details und Screenshots stehen in `Gedächtnis.md`.

Kategorien sind ein eigener Hauptbereich. Speichere Ober- und
Unterkategorien über `parent_id`, verhindere Selbstbezug und Zyklen und
erlaube nur Eltern derselben Einnahmen-/Ausgabenart. In allen Auswahlfeldern
ist der vollständige Pfad (`Oberkategorie › Unterkategorie`) anzuzeigen.

Ein vollständiger QIF-Export kann viele Konten, Kategorien, Klassen,
Vorlagen und Wertpapierabschnitte enthalten. Solche Pakete dürfen niemals
still in ein einzelnes Zielkonto importiert werden. Analysiere zuerst
Encoding, Header und Kontoblöcke, zeige eine Zuordnungsvorschau und übernimm
erst nach ausdrücklicher Bestätigung. Reale Referenzdateien bleiben außerhalb
des Repositorys; Tests verwenden nur synthetische oder anonymisierte Daten.

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

## Qualitätsschleife

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
