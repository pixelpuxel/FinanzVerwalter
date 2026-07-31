# Anforderungsmatrix FinanzVerwalter

Stand: 31.07.2026

Diese Matrix ist die überprüfbare Soll-Ist-Sicht zur externen Masterdatei.
`Erfüllt` bedeutet, dass Domänenlogik, Persistenz, Oberfläche und Tests für
den genannten Umfang vorliegen. `Teilweise` bezeichnet ausdrücklich keinen
fertigen Funktionsbereich.

| Priorität | Anforderung | Status | Nachweis / nächste Lücke |
|---|---|---|---|
| P0 | Lokale Finanzdatei, SQLite-WAL, Migrationen, Audit | Erfüllt | Migrationen 1–28, Integritätstest, append-only Auditereignisse |
| P0 | Konten und Kontogruppen | Erfüllt für lokalen Kern | Vollständige Stammdaten und neun fachliche Standardgruppen; Migration 12 ordnet ungruppierte Bestandskonten und der QIF-Paketimport neue Konten typgerecht zu; externe und lokale Konten werden beim Simulatorabruf sichtbar eins zu eins zugeordnet |
| P0 | Kontoblatt mit laufendem Saldo, Suche und Status | Teilweise | Register, kontenweiser laufender Saldo einschließlich Bestands- und Ansichtenmigration, Ein-/Zweizeilenmodus, Konto-/Status-/Kategorie-/Klassen-/Zeitraumfilter, Mehrfachauswahl, währungsgetrennte Summen, atomare Massenorganisation, vollständige Kategorie- und Klassenpfade, elf dynamische Standardspalten, benannte Ansichten, persistente Mehrkonto-Tabs, F3-Auswahlfilter, direkter PDF-/Systemdruck, zehn anpassbare konfliktgeprüfte Shortcuts, währungs-/splitkorrekter Minireport, zweites Kontoblatt sowie semantische Saldo-/Filter-/Tabellen-/Zellbeschriftungen und getrennt bedienbare Tabaktionen vorhanden; vollständige sichtbare Tastatur-/VoiceOver-/UI-Abnahme fehlt |
| P0 | Kategorien und Unterkategorien | Erfüllt für lokalen Kern | Beliebig tiefe Hierarchie, Zyklen-/Artprüfung, vollständige Pfade, Beschreibung, Budgetierbarkeit, Standard-MwSt.-Schlüssel sowie deutsche und optionale US-Steuerzuordnung |
| P0 | Klassen/Mehrfach-Tags | Erfüllt für lokalen Kern | Hierarchische Tags auf Buchungen und Splits, Kreis-/Elternprüfung, vollständige Pfade, eigenständige Filter in Einzel-/Zweit-/Sammelkontenblatt, benannte Ansichten und atomare gemeinsame Kategorie-/Tag-Massenbearbeitung mit Schutzregeln vorhanden |
| P0 | Empfänger/SmartFill | Erfüllt für lokalen Kern | Stammdaten, Aliase, beliebig viele versionierte Bankverbindungen mit genau einem aktiven Standard, sichere unveränderliche Überweisungs- und Lastschriftschnappschüsse, Standardkategorie/-konto/-klassen, geprüfte SEPA-Gläubiger-ID, mehrere versionierte Mandate sowie deterministische SmartFill-Vorschläge mit Präfix-, Nutzungs-, Namens- und UUID-Rangfolge, sicherer Freitextentkopplung und Buchungsverknüpfung vorhanden |
| P0 | Buchungen, Splits und Transfers | Teilweise | Centgenaue Buchungen, Splitinvariante, atomare Transfers, frei definierbare MwSt.-Schlüssel einschließlich 0 %, automatische/manuelle Brutto-Netto-Steuer-Berechnung mit Rundung je Splitzeile, bestätigtes atomares Mehrfachlöschen sowie frische Duplikate, deutsche TSV-Kopie und atomarer auditierter Kontowechsel mit Abgleich-/Umbuchungs-/Währungs-/Zielkontoschutz vorhanden; Fremdwährung, Anhänge und allgemeines Buchungs-Undo fehlen |
| P0 | Regeln | Erfüllt für lokalen Kern | Versionierte rekursive AND/OR-Ausdrücke, 16 fachliche Felder, acht Operatoren einschließlich Regex/Bereich/Leerprüfung, Kategorie-/Empfänger-/Notiz-/Tag-/Text-/Splitaktionen, Priorität, Konfliktanzeige, buchungsweise Vorher/Nachher-Auswahl, atomarer Commit, vollständiges konfliktgeschütztes Undo und Regel aus Buchung; konfliktfreie Regeln laufen sichtbar in der Bankabrufvorschau, Konflikte verhindern die automatische Anwendung |
| P0 | Import und Migration | Teilweise | CSV/TSV, Einzelkonto-QIF, Mehrkonten-QIF, OFX-2-XML, OFX-1/QFX-SGML, MT940 sowie camt.052/053/054 mit Mehrkontenzuordnung, Vorschau/Paket-Idempotenz, gestuftem Buchungs-Matching, konfigurierbarem Datumsfenster, expliziter Entscheidung, erhaltener lokaler Anreicherung und eindeutiger externer Bank-ID; zusätzlich sichere pain.001.001.09-/pain.008.001.08-Auftragsimporte mit exakter Stammdatenzuordnung, Entwurfssemantik und Historie; Profilassistent und weitere ISO-20022-Formate fehlen |
| P0 | Kontoabgleich | Erfüllt für lokalen Kern | Anfangs-/Endsaldo, Auszugsdatum, explizite Buchungsauswahl, markierte Summe, Differenz, doppelt bestätigte Ausgleichsbuchung, Buchungsschutz, unveränderliche Positionshistorie und Rücknahme des jüngsten aktiven Abgleichs mit Audit vorhanden |
| P0 | Sammelkontoblatt | Erfüllt für lokalen Kern | Frei kombinierbare offene Konten, chronologische reale und regelmäßige Zukunft bis 365 Tage, echte kontenweise Salden, blaue Heute-/Zukunftsgrenze, unabhängige Status-/Kategorie-/Zeitraum-/Textfilter, Warnung bei gefilterter Bewegungssumme, währungsgetrennte Summen, benannte Kombinationen, geschützte Mehrfachkategorisierung, Systemdruck/PDF, zwei gleichzeitig geteilte Sammelansichten und direkte Berichtsaufrufe für Sichtmenge, Empfänger, Kategorie oder Klasse/Tag vorhanden |
| P0 | Berichte, Druck und Export | Teilweise | Live-Querymodell mit allen P0-Filtern, Splitauflösung ohne Doppelzählung, währungsgetrennte Gruppen, Drill-down, versionierte Vorlagen, CSV-Golden-Test und mehrseitiges A4-PDF in Hoch-/Querformat mit semantischem Test und Renderprüfung vorhanden; das Kontoblatt besitzt direkten Systemdruck, die Berichtswerkstatt noch nicht; zweite Dimension, weitere Standardberichte sowie XLSX/HTML fehlen |
| P0 | Backup und Restore | Teilweise | Atomare SQLite-Sicherung, Validierung, Sicherheitskopie vor Restore; Rotation, Autosicherung, Verschlüsselung, Dateiwechsel und Reparaturkopie fehlen |
| P1 | Banking-Adaptervertrag und Read-only-Abruf | Erfüllt für Simulator-Kern | Getrennter Read-only-Adaptervertrag, deterministischer Simulator für Konten, Salden, gebuchte/vorgemerkte Umsätze, Daueraufträge und Terminüberweisungen, explizite Kontenzuordnung, Regel-/Matching-Vorschau, Abbruchschutz, Rohhash, Diagnose, Abrufhistorie und atomarer Commit; echte FinTS-/PSD2-Verbindungen, SCA-Dialoge, Depots und Kurse fehlen und bleiben sichtbar deaktiviert |
| P1 | Zahlungsverkehr | Teilweise | SEPA-/Echtzeit-/Terminauftrag, unveränderliche Stammdatenschnappschüsse, SEPA-Core-Lastschrift, atomare Sammler, SCA-Simulation, Idempotenz, versionierte pain.001.001.09-/pain.008.001.08-Exporte und sichere Importe mit exakter Konto-/Empfänger-/Bank-/Mandatszuordnung, selektiver doppelter Bestätigung, reinen Entwürfen, Sammlerrekonstruktion und persistenter Historie; sicherer pain.002.001.10-Statusimport; lokale Daueraufträge; offline EPC069-12-v3.1-QR-Bildscan mit strengem Parser, sichtbarer Editorprüfung, optionalem persistentem SEPA-Zweckcode und pain.001-Rundlauf; ein versionierter Feiertagskalender fehlt |
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
| Härtung | Accessibility/E2E | Teilweise | Stabile AX-Identifier und semantische Werte für Kontoblattfilter, Saldo, Haupt-/zweite-/Sammeltabelle, vollständige Zellwerte und getrennte Tabaktionen; der Kontextmonitor schützt Texteingabe und gibt Eingabe/Escape ohne Dialog frei; vollständige sichtbare Tastatur-, VoiceOver- und UI-Testabdeckung fehlt |
| Auslieferung | macOS-Release | Teilweise | Lokale Release-App installiert; Signierung, Installer, Update/Rollback fehlen |
| Auslieferung | Windows-Installer | Offen | Native SwiftUI-Entscheidung liefert derzeit keine Windows-Anwendung |
| Dokumentation | Architektur, Handbücher, SBOM, Abweichungen | Teilweise | README, Gedächtnis, PortalPrompt, ADRs und diese Matrix; Benutzer-/Migrations-/Adminhandbuch, Threat Model, SBOM und Changelog fehlen |

## Aktuelle Reihenfolge

1. Vollständige Kontoblatt-Tastatur-/Accessibility-/UI-Abnahme nach dem
   manuellen Entsperren des Macs.
2. Den vorhandenen pain.001-/pain.008-/pain.002- und EPC-QR-Kern mit weiteren
   synthetischen Bankvarianten härten; danach einen versionierten
   Feiertagskalender ergänzen.
3. Produktive FinTS-/PSD2-Adapter erst nach geklärter Provider-, Lizenz-,
   SCA-, Datenschutz- und Sicherheitsarchitektur.
