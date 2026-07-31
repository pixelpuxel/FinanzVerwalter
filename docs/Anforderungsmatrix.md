# Anforderungsmatrix FinanzVerwalter

Stand: 31.07.2026

Diese Matrix ist die überprüfbare Soll-Ist-Sicht zur externen Masterdatei.
`Erfüllt` bedeutet, dass Domänenlogik, Persistenz, Oberfläche und Tests für
den genannten Umfang vorliegen. `Teilweise` bezeichnet ausdrücklich keinen
fertigen Funktionsbereich.

| Priorität | Anforderung | Status | Nachweis / nächste Lücke |
|---|---|---|---|
| P0 | Lokale Finanzdatei, SQLite-WAL, Migrationen, Audit | Erfüllt | Migrationen 1–21, Integritätstest, append-only Auditereignisse |
| P0 | Konten und Kontogruppen | Erfüllt für lokalen Kern | Vollständige Stammdaten und neun fachliche Standardgruppen; Migration 12 ordnet ungruppierte Bestandskonten und der QIF-Paketimport neue Konten typgerecht zu; externe und lokale Konten werden beim Simulatorabruf sichtbar eins zu eins zugeordnet |
| P0 | Kontoblatt mit laufendem Saldo, Suche und Status | Teilweise | Register, kontenweiser laufender Saldo einschließlich Bestands- und Ansichtenmigration, Ein-/Zweizeilenmodus, Konto-/Status-/Kategorie-/Zeitraumfilter, Mehrfachauswahl, währungsgetrennte Summen, atomare Massenkategorisierung, vollständige Kategoriepfade, elf dynamische Standardspalten, benannte Ansichten, persistente Mehrkonto-Tabs, F3-Auswahlfilter, direkter PDF-/Systemdruck, zehn anpassbare konfliktgeprüfte Shortcuts, währungs-/splitkorrekter Minireport für Empfänger/Kategorie/Klasse sowie zweites Kontoblatt mit eigener Konto-/Filterwahl und Saldo vorhanden; vollständige Tastatur-/AX-/UI-Abnahme fehlt |
| P0 | Kategorien und Unterkategorien | Erfüllt für lokalen Kern | Beliebig tiefe Hierarchie, Zyklen-/Artprüfung, vollständige Pfade, Beschreibung, Budgetierbarkeit, Standard-MwSt.-Schlüssel sowie deutsche und optionale US-Steuerzuordnung |
| P0 | Klassen/Mehrfach-Tags | Teilweise | Hierarchische Tags auf Buchungen und Splits vorhanden; eigenständige Klassenfilter und Massenbearbeitung fehlen |
| P0 | Empfänger/SmartFill | Teilweise | Stammdaten, Aliase, Bankdaten und Vorschläge vorhanden; Mandate und Gläubiger-ID fehlen |
| P0 | Buchungen, Splits und Transfers | Teilweise | Centgenaue Buchungen, Splitinvariante, atomare Transfers, frei definierbare MwSt.-Schlüssel einschließlich 0 %, automatische/manuelle Brutto-Netto-Steuer-Berechnung mit Rundung je Splitzeile sowie bestätigtes, atomares Mehrfachlöschen mit Schutz abgeglichener Buchungen vorhanden; Fremdwährung, Anhänge, Duplizieren/Verschieben und Undo fehlen |
| P0 | Regeln | Erfüllt für lokalen Kern | Versionierte rekursive AND/OR-Ausdrücke, 16 fachliche Felder, acht Operatoren einschließlich Regex/Bereich/Leerprüfung, Kategorie-/Empfänger-/Notiz-/Tag-/Text-/Splitaktionen, Priorität, Konfliktanzeige, buchungsweise Vorher/Nachher-Auswahl, atomarer Commit, vollständiges konfliktgeschütztes Undo und Regel aus Buchung; konfliktfreie Regeln laufen sichtbar in der Bankabrufvorschau, Konflikte verhindern die automatische Anwendung; SmartFill-Nutzungsgewichtung fehlt |
| P0 | Import und Migration | Teilweise | CSV/TSV, Einzelkonto-QIF und Mehrkonten-QIF mit Vorschau/Paket-Idempotenz, gestuftem Buchungs-Matching, konfigurierbarem Datumsfenster, expliziter Entscheidung, erhaltener lokaler Anreicherung und eindeutiger externer Bank-ID sowie pain.001.001.09-Export; Profilassistent, OFX/QFX, MT940, camt und ISO-20022-Import fehlen |
| P0 | Kontoabgleich | Erfüllt für lokalen Kern | Anfangs-/Endsaldo, Auszugsdatum, explizite Buchungsauswahl, markierte Summe, Differenz, doppelt bestätigte Ausgleichsbuchung, Buchungsschutz, unveränderliche Positionshistorie und Rücknahme des jüngsten aktiven Abgleichs mit Audit vorhanden |
| P0 | Sammelkontoblatt | Teilweise | Frei kombinierbare offene Konten, chronologische reale und regelmäßige Zukunft bis 365 Tage, echte kontenweise Salden, blaue Heute-/Zukunftsgrenze, unabhängige Status-/Kategorie-/Zeitraum-/Textfilter, Warnung bei gefilterter Bewegungssumme, währungsgetrennte Summen, benannte Kombinationen, geschützte Mehrfachkategorisierung sowie Systemdruck/PDF der sichtbaren Spalten vorhanden; zwei gleichzeitig geteilte Sammelansichten und direkte Berichtsaufrufe fehlen |
| P0 | Berichte, Druck und Export | Teilweise | Live-Querymodell mit allen P0-Filtern, Splitauflösung ohne Doppelzählung, währungsgetrennte Gruppen, Drill-down, versionierte Vorlagen, CSV-Golden-Test und mehrseitiges A4-PDF in Hoch-/Querformat mit semantischem Test und Renderprüfung vorhanden; das Kontoblatt besitzt direkten Systemdruck, die Berichtswerkstatt noch nicht; zweite Dimension, weitere Standardberichte sowie XLSX/HTML fehlen |
| P0 | Backup und Restore | Teilweise | Atomare SQLite-Sicherung, Validierung, Sicherheitskopie vor Restore; Rotation, Autosicherung, Verschlüsselung, Dateiwechsel und Reparaturkopie fehlen |
| P1 | Banking-Adaptervertrag und Read-only-Abruf | Erfüllt für Simulator-Kern | Getrennter Read-only-Adaptervertrag, deterministischer Simulator für Konten, Salden, gebuchte/vorgemerkte Umsätze, Daueraufträge und Terminüberweisungen, explizite Kontenzuordnung, Regel-/Matching-Vorschau, Abbruchschutz, Rohhash, Diagnose, Abrufhistorie und atomarer Commit; echte FinTS-/PSD2-Verbindungen, SCA-Dialoge, Depots und Kurse fehlen und bleiben sichtbar deaktiviert |
| P1 | Zahlungsverkehr | Teilweise | SEPA-/Echtzeit-/Terminauftrag, IBAN, unveränderliche Bestätigung, SCA, Idempotenz, versionierter pain.001.001.09-Export sowie lokale Daueraufträge mit Pause/Ende, Wochenendregel, genau-einmaliger Entwurfserzeugung und Historie; Feiertagskalender, Lastschrift, Sammler, EPC-QR sowie pain.001-Import, pain.008 und pain.002 fehlen |
| P1 | Kalender und Prognose | Teilweise | Regelmäßige Vorgänge, Monatsende und 30/90/180/365-Tage-Prognose; Wochenansicht, Ausnahmen, Feiertage, Drag-and-drop und Szenarien fehlen |
| P1 | Budgets | Teilweise | Mehrere Budgets, Geschäftsjahr, Monatsplan, Ist/Abweichung, Roll-over-Schalter; Jahreswerte, Reserve, Kopie und Berichte fehlen |
| P1 | Wertpapiere und Depots | Teilweise | Stammdaten, Mikroeinheiten, FIFO-Lots, Allokation und Kurse; weitere Transaktionen, Lotmethoden, Performance und Import fehlen |
| P1 | Kredite und Vermögen | Teilweise | Versionierte Zinsen, Sondertilgung, Tilgungsplan, Werte und Nettoanteil; automatische Ratensplits, Ist-Abgleich und Szenarien fehlen |
| P1 | Verträge und Inventar | Teilweise | Stammdaten, Fristen, Kosten und Werte; produktiver Anhangsspeicher, Erinnerungsjobs und Export fehlen |
| P1 | Freistellungsaufträge | Offen | Datenmodell, gesetzliche Regelpakete, Kontenzuordnung und Nutzung fehlen |
| P2 | Planner, Sparziele, Vermietung, Geschäft | Offen | Optionale Module dürfen P0/P1 nicht blockieren |
| Härtung | Mehrwährungen | Offen | Kontowährung existiert; FX-Kurse, Originalbetrag, Rundungsregeln und währungskorrekte Summen fehlen |
| Härtung | Anhänge/OCR | Offen | Metadatentabellen bei Vertrag/Inventar; hashadressierter Store und sichere Öffnung fehlen |
| Härtung | Security/Privacy | Teilweise | Lokal, keine Telemetrie, keine TAN-Persistenz; Datenbankverschlüsselung, Keychain-Konzept, Sperre und Threat Model fehlen |
| Härtung | Referenzdatensatz/Performance | Offen | Demo ist klein; 100.000-Buchungen-Ziele sind nicht gemessen |
| Härtung | Accessibility/E2E | Teilweise | Einzelne Accessibility-Sichtprüfungen; vollständige Tastatur-, AX- und UI-Testabdeckung fehlt |
| Auslieferung | macOS-Release | Teilweise | Lokale Release-App installiert; Signierung, Installer, Update/Rollback fehlen |
| Auslieferung | Windows-Installer | Offen | Native SwiftUI-Entscheidung liefert derzeit keine Windows-Anwendung |
| Dokumentation | Architektur, Handbücher, SBOM, Abweichungen | Teilweise | README, Gedächtnis, PortalPrompt, ADRs und diese Matrix; Benutzer-/Migrations-/Adminhandbuch, Threat Model, SBOM und Changelog fehlen |

## Aktuelle Reihenfolge

1. Vollständige Kontoblatt-Tastatur-/Accessibility-/UI-Abnahme, zwei
   gleichzeitig geteilte Sammelansichten und direkte Berichtsaufrufe.
2. OFX/QFX-, MT940- und camt-Import über denselben sicheren Commitpfad.
3. SmartFill-Nutzungsgewichtung und erweiterte Klassen-Massenbearbeitung.
4. Produktive FinTS-/PSD2-Adapter erst nach geklärter Provider-, Lizenz-,
   SCA-, Datenschutz- und Sicherheitsarchitektur.
