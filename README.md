# FinanzVerwalter – eigenständige Desktop-Finanzverwaltung

Native, local-first macOS-App für private Finanzverwaltung. Das Projekt ist
eine vollständige Neuentwicklung und verwendet keine Quellteile aus anderen
Apps im Workspace. Mindestversion ist macOS 14.4.

## Build

```bash
xcodebuild \
  -project FinanzVerwalter.xcodeproj \
  -scheme FinanzVerwalter \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Tests

```bash
xcodebuild \
  -project FinanzVerwalter.xcodeproj \
  -scheme FinanzVerwalter \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Start

Das Buildprodukt liegt unter:

`build/DerivedData/Build/Products/Debug/FinanzVerwalter.app`

Für eine isolierte Sichtprüfung mit lokal erzeugten Beispieldaten:

```bash
open -n build/DerivedData/Build/Products/Debug/FinanzVerwalter.app --args -demo
```

Der normale Start verwendet die lokale Finanzdatei:

`~/Library/Application Support/FinanzVerwalter/Meine Finanzen.qdata`

## QIF-Import

Einzelne Kontoblätter und vollständige Mehrkontenpakete werden unterschieden.
Bei einem Paket zeigt FinanzVerwalter vor der ausdrücklichen Übernahme die
erkannten Konten, neuen Kategorien, Buchungen und nicht unterstützten Bereiche
an. Konten, hierarchische Kategorien und normale Kontobuchungen werden
anschließend atomar und idempotent gespeichert. Depot-, Klassen- und
Merkpostenbereiche werden derzeit sichtbar ausgelassen, statt sie in ein
unpassendes Kontoblatt zu schreiben.

## OFX-/QFX-Kontoauszüge

OFX 2.x (XML) und klassische OFX-1.x-/QFX-SGML-Dateien werden lokal und ohne
zusätzliche Bibliothek gelesen. Mehrere Bank- und Kreditkartenkonten einer
Datei müssen vor der Vorschau jeweils einem vorhandenen Konto zugeordnet
werden; eindeutige Kontonummern werden vorgeschlagen. Die Währung muss
übereinstimmen. FITID, Buchungs- und Wertstellungsdatum, Empfänger, Memo,
Referenz und Buchungstyp fließen in die normale Importvorschau ein.

Dateien sind auf 50 MB und 200.000 Datensätze begrenzt. Fehlerhafte
Datensätze werden mit Begründung abgewiesen. Erst die ausdrückliche
Bestätigung schreibt alle gewählten Buchungen gemeinsam; Paket-Hash,
Bank-ID-Matching und der bestehende atomare Commit schützen vor Dubletten.

## MT940- und camt.05x-Kontoauszüge

Der Kontoauszugsdialog von FinanzVerwalter liest außerdem MT940 (`.sta`, `.mt940`)
sowie ISO-20022-camt.052/053/054 (`.xml`, `.c53`, `.c54`). MT940 unterstützt
mehrere Auszüge, `:61:`-Buchungen und strukturierte `:86:`-Unterfelder. Der
camt-Import löst Sammelbuchungen über `TxDtls` auf und übernimmt Valuta,
Bankreferenz, End-to-End-ID, Mandatsreferenz, Gegenkonto-IBAN/-BIC und
Verwendungszweck.

Beide Formate verwenden dieselbe explizite Mehrkontenzuordnung, Vorschau,
Matchinglogik, 50-MB-/200.000-Datensatz-Grenze und atomare Übernahme wie
OFX/QFX. Fehlerhafte Buchungen bleiben einzeln sichtbar. camt-Dateien mit
DTD- oder ENTITY-Deklarationen werden vor dem XML-Parsing vollständig
abgewiesen; externe Entitäten werden nie aufgelöst.

### Sicherer Abgleich mit vorhandenen Buchungen

CSV-/TSV-, QIF-, OFX/QFX-, MT940- und camt-Vorschauen vergleichen jede importierte Buchung gestuft mit
vorhandenen Umsätzen desselben Kontos. Exakte Bank-IDs, Betrag/Währung,
Buchungs- beziehungsweise Wertstellungsdatum, Referenzen, IBAN, Empfänger und
Verwendungszweck fließen in einen nachvollziehbaren Trefferwert ein. Das
Datumsfenster ist im Importdialog von 0 bis 14 Tagen einstellbar.

Jede Zeile bleibt vor dem Commit sichtbar und bietet `Neu importieren`,
`Überspringen` oder den konkreten vorhandenen Umsatz mit Datum, Betrag und
Score. Nur ein eindeutiger starker Treffer wird vorgeschlagen; mehrdeutige
oder schwache Kandidaten werden niemals still zusammengeführt. Beim
bestätigten Abgleich bleiben lokale Kategorien, Notizen, Splits, Tags und
Mehrwertsteuer erhalten. Eine externe Transaktions-ID ist je Konto und
Provider eindeutig.

## Tastatur und Buchungsvorlagen

Unter `Einstellungen › Tastaturkurzbefehle` sind neue Buchung, Speichern,
Suche, Kontoabgleich, Splitdialog, Buchungsvorlage, F3-Filter, Löschen,
Übernehmen und Abbrechen vollständig sichtbar. Taste sowie Command-, Shift-,
Option- und Control-Modifikator sind anpassbar. Doppelte Belegungen und
ungeschützte Buchstaben-/Zifferntasten werden vor dem Anwenden abgelehnt.

Eine im Kontoblatt markierte Buchung kann mit dem zugeordneten Befehl als
Vorlage gespeichert und aus dem Menü `Vorlagen` als neuer Entwurf geöffnet
werden. Vorlagen gehören zur jeweiligen Finanzdatei. Sie übernehmen auch
Splits und Tags, aber niemals altes Datum, Belegnummer, Transfer- oder
Importidentität. Eine einzelne Umbuchungsseite ist keine zulässige Vorlage.

Kontoblatt, zweites Kontoblatt und Sammelkontoblatt besitzen stabile
Accessibility-Bezeichner. VoiceOver erhält für jede dynamische Zelle den
Spaltentitel und den vollständigen Wert – insbesondere den ungekürzten
Kategoriepfad und Saldo. Konto-Tabs bieten Auswahl und Schließen als getrennte
Aktionen. Eingabe und Escape bleiben außerhalb geöffneter Dialoge der
Tabellen- beziehungsweise Systembedienung vorbehalten.

Kategorie- und Klassenfilter arbeiten unabhängig voneinander. Klassen/Tags
werden überall mit ihrem vollständigen Hierarchiepfad angezeigt und gehören
auch zu benannten Einzel- und Sammelkontoblatt-Ansichten. Die gemeinsame
Mehrfachbearbeitung kann Kategorie und/oder die vollständige Tag-Menge einer
Auswahl in einem atomaren Schritt ersetzen. Abgeglichene Buchungen und
Umbuchungen bleiben geschützt; eine reine Tag-Änderung ist auch bei einer
Splitbuchung möglich, ohne deren getrennte Split-Tags anzutasten.

Der Buchungseditor bietet SmartFill für gepflegte Empfängerakten. Die Suche
berücksichtigt kanonische Namen und Aliase ohne Unterschied bei Großschreibung
oder Diakritika. Präfixtreffer stehen vor bloßen Teiltreffern; danach folgen
bisherige Verwendung, Name und UUID als stabile Sortierung. Erst die bewusste
Auswahl übernimmt den kanonischen Namen und noch freie Standardwerte für Konto,
Kategorie und Klassen/Tags. Wird der Text anschließend manuell verändert, löst
FinanzVerwalter die Aktenverknüpfung, damit kein falscher Empfänger gespeichert
wird.

Empfängerakten speichern außerdem eine nach Mod 97 geprüfte SEPA-Gläubiger-ID
und beliebig viele eindeutige Mandate mit Referenz, Unterschriftsdatum,
Sequenztyp, Notiz und Aktivstatus. Der Buchungseditor kann ein aktives Mandat
aus der verknüpften Akte auswählen und schreibt Gläubiger-ID und
Mandatsreferenz dauerhaft in die Buchung. Eine einzelne aktive Mandatsakte wird
bei bewusster Empfängerauswahl automatisch vorgeschlagen; mehrere Mandate
bleiben eine ausdrückliche Auswahl.

Jede Empfängerakte kann außerdem beliebig viele benannte Bankverbindungen mit
Kontoinhaber, geprüfter IBAN, optionaler BIC, Bankname und Aktivstatus führen.
Genau eine aktive Verbindung kann als Standard markiert sein. Im
Zahlungsverkehr übernimmt eine bewusste Auswahl die Bankdaten in den Entwurf
und verknüpft die verwendete Akte und Bankverbindung. Vor dem Speichern wird
die Übereinstimmung nochmals geprüft; der Auftrag bewahrt anschließend seinen
unveränderlichen Bankdaten-Schnappschuss, auch wenn die Empfängerakte später
bearbeitet wird. Eine vollständig manuelle Eingabe bleibt möglich.

`Zahlungsverkehr › Dateiimporte` liest lokale `pain.001.001.09`- und
`pain.008.001.08`-Dateien ausschließlich als neue Entwürfe ein. Vor der
Übernahme zeigt eine unveränderliche Vorschau jede Position, das exakt über
Name, IBAN und gegebenenfalls BIC zugeordnete EUR-Konto sowie Empfänger,
Bankverbindung und bei Lastschriften das aktive Mandat. Unklare oder
widersprüchliche Zuordnungen werden nicht geraten. Erst Auswahl und zweite
Bestätigung speichern die Entwürfe und gegebenenfalls einen vollständig
enthaltenen Sammler atomar. Der Import sendet nichts an eine Bank, erzeugt
keine Buchung und ist über den SHA-256-Dateifingerabdruck idempotent. Eine
persistente Importhistorie hält auch ausgelassene Positionen nachvollziehbar.

Der Überweisungseditor kann außerdem ein lokales Rechnungsbild mit genau
einem EPC-QR-Code nach EPC069-12 Version 3.1 lesen. Die Auswertung erfolgt
offline über macOS Vision und füllt Empfänger, IBAN/BIC, optionalen Betrag,
SEPA-Zweckcode, Gläubigerreferenz oder Verwendungszweck sowie den Hinweis nur
in den sichtbaren Editor. Sie legt niemals selbst einen Auftrag an. BCD,
Version 001/002, Zeichensatz, SCT, die 331-Byte-Grenze, Feldlängen,
IBAN/BIC, EUR-Betragsgrenzen, ISO-11649-RF-Prüfsumme und die alternative
Referenz-/Freitextbelegung werden validiert. Bilder über 20 MB, sehr große
Abmessungen, kein oder mehrere QR-Codes werden abgewiesen.

## Regeln

Regeln besitzen eine sichtbare Priorität und versionierte AND/OR-
Bedingungsgruppen. Neben Empfänger und Zweck können unter anderem Konto,
IBAN, BIC, Betrag/Vorzeichen, Buchungstext, Referenzen, Zeitraum, Status und
Herkunft mit Gleichheit, Textoperatoren, Regex, Bereichen oder
Leerprüfungen ausgewertet werden. Ungültige Regex- und Betragsbedingungen
werden vor dem Speichern abgelehnt.

Aktionen können Kategorie, Empfänger, Notiz, Klassen/Tags und
Verwendungszweck verändern oder einen centgenauen Einzeilen-Split erzeugen.
Vor jeder Anwendung zeigt FinanzVerwalter die betroffenen Buchungen mit
Vorher/Nachher-Werten; nur ausdrücklich ausgewählte Zeilen werden atomar
geändert. Widersprüchliche Zielfelder anderer Regeln erscheinen als
Konflikthinweis. Das letzte Regelpaket kann vollständig zurückgenommen
werden, solange keine seiner Buchungen zwischenzeitlich bearbeitet wurde.

Aus dem Kontextmenü einer einfach kategorisierten Kontoblattbuchung lässt
sich eine kontospezifische Regel erzeugen. Sie wird gespeichert, aber nie
unbemerkt auf Bestandsdaten angewandt.

## Schreibgeschützter Banking-Abruf

`Banking` besitzt einen adapterunabhängigen, ausschließlich lesenden
Abrufvertrag. Der derzeit aktivierbare lokale Simulator benötigt weder
Bankzugang noch TAN und liefert reproduzierbar Konten, Salden, gebuchte und
vorgemerkte Umsätze, Daueraufträge sowie Terminüberweisungen. FinTS/HBCI,
PSD2/Open Banking und Web-Connectoren sind als getrennte Providerarten
modelliert, aber ausdrücklich deaktiviert; die App behauptet keine
produktive Bankanbindung.

Lokale und externe Konten werden sichtbar eins zu eins zugeordnet. Nach dem
Abruf zeigt eine Vorschau jede Buchung samt Importentscheidung, angewandten
Regeln, Banksalden, Beständen und technischer Diagnose. Der bereits für
Dateiimporte verwendete gestufte Abgleich verhindert doppelte externe IDs
und erhält lokale Kategorien, Notizen, Splits und Tags. Erst nach Bestätigung
werden alle neuen oder abgeglichenen Buchungen, Salden, Bestände und das
Abrufprotokoll gemeinsam in einer SQLite-Transaktion gespeichert. Abbruch
oder ein einziger fehlgeschlagener Vorgang verändern keine Fachdaten; rohe
Bankantworten werden nicht gespeichert, nur ihr SHA-256-Hash.

Reale Finanzexporte gehören nicht in das Repository; `.gitignore` schließt
QIF-, OFX-, QFX-, STA-, MT940-, C53- und C54-Dateien ausdrücklich aus.

## Kontoblatt

Das Kontoblatt filtert nach Konto, Status, vollständigem Kategoriepfad und
Zeitraum. Mehrere Buchungen können ausgewählt und nach einer Vorschau mit
währungsgetrennten Summen gemeinsam kategorisiert werden. Die Änderung läuft
atomar; enthält die Auswahl abgeglichene Buchungen, Umbuchungen oder
Splitbuchungen, wird sie vollständig abgewiesen. Kategoriepfade erscheinen
einzeilig mit mittiger Kürzung und vollständig im Tooltip.

Das Kontextmenü einer Buchung bietet Bearbeiten, Duplizieren, Kopieren und
Verschieben. Duplizieren öffnet einen frischen Buchungsentwurf mit neuen
Transaktions- und Split-IDs, heutigem Datum und ohne Import-, Referenz- oder
Umbuchungsidentität; eine abgeglichene oder stornierte Quelle wird als
normale gebuchte Buchung vorbereitet. Kopieren legt Datum, Empfänger,
Verwendungszweck, vollständigen Kategoriepfad, Betrag und Währung als
tabulatorgetrennte deutsche Zeile in die Zwischenablage. Verschieben erhält
sämtliche Buchungs-, Split-, Steuer- und Organisationsdaten und ist nur in
ein anderes offenes Konto derselben Währung möglich. Abgeglichene Buchungen
und einzelne Umbuchungsseiten bleiben geschützt. Die Kontoänderung erfolgt
atomar und wird in der Auditspur protokolliert.

Direkt rechts neben dem Betrag steht der kontenweise laufende Saldo. Die
Darstellung kann dauerhaft zwischen einer kompakten Einzeile und einer
zweizeiligen Ansicht mit Wertstellung, Memo, Referenz und Tags umgeschaltet
werden. Bestands- und QIF-Konten werden in Bankkonten, Kreditkarten, Bargeld,
Depots, Kredite, Vermögen, Verbindlichkeiten, Forderungen oder Sonstige
einsortiert. Datum, Wertstellung, Belegnummer, Status, Empfänger,
Verwendungszweck, Kategorie, Klasse/Tags, Konto, Betrag und Saldo lassen sich
vollständig ein- oder ausblenden. Benannte Ansichten speichern Konto, Filter,
Zeitraum, Zeilenmodus und Spaltenauswahl und können später wieder geladen
oder gelöscht werden. Beim ersten Start nach dem Saldo-Update wird die Spalte
einmalig auch in vorhandene Spalteneinstellungen und benannte Ansichten
aufgenommen; anschließend bleibt sie wie jede andere Spalte frei schaltbar.
Das Menü `Ausgabe` druckt
das gefilterte Kontoblatt direkt über den macOS-Druckdialog oder exportiert
es als mehrseitiges PDF. Dabei werden exakt die sichtbaren Spalten mit
wiederholten Tabellenköpfen, Filterbeschreibung und Seitenzahlen ausgegeben.

Mehrere Konten bleiben als horizontale Kontoblatt-Tabs geöffnet. Jeder Tab
zeigt Name und aktuellen Saldo, kann direkt gewechselt oder geschlossen
werden und wird in stabiler Reihenfolge lokal gespeichert; gelöschte Konten
werden beim Wiederherstellen sicher ignoriert. `⌘N` öffnet eine neue
Buchung, `⌘S` speichert den geöffneten Buchungsdialog, `⌘F` fokussiert die
globale Suche, `⌘R` öffnet den Abgleich und `⌘⇧S` startet beziehungsweise
aktiviert die Splitbuchung. `F3` übernimmt aus genau einer markierten Buchung
wahlweise Empfänger, Verwendungszweck, Kategorie, Konto oder Status als
Filter; das gewünschte Feld wird direkt im Kontenblatt gewählt.

Der einblendbare rechte Minireport folgt genau einer markierten Buchung und
wertet wahlweise deren Empfänger, vollständige Kategorie oder erste
Klasse/Tag aus. Einnahmen, Ausgaben und Saldo bleiben je Währung getrennt;
bei Splitbuchungen zählt nur der fachlich passende Splitbetrag. Die letzten
passenden Buchungen bleiben als kompakte Detailhistorie sichtbar.

Mit `Teilen` öffnet sich daneben ein zweites Kontoblatt für ein anderes
Konto. Es besitzt eine eigene Kontowahl sowie unabhängige Status-, Kategorie-
und Zeitraumfilter, zeigt vollständige Kategoriepfade, Betrag und laufenden
Saldo und kann Buchungen per Doppelklick bearbeiten. Minireport und geteilte
Ansicht sind auf engem Raum wechselseitig, damit das Hauptkontenblatt nicht
unter eine unbrauchbare Mindestbreite gedrückt wird.

## Sammelkontoblatt

Das Sammelkontoblatt kombiniert frei wählbare offene Konten mit eigenen
Status-, vollständigen Kategorie-, Zeitraum- und Volltextfiltern. Optional
werden deterministisch erzeugte regelmäßige Vorgänge für die kommenden 365
Tage eingeblendet. Die Tabelle bleibt chronologisch, markiert den ersten
Zukunftsvorgang blau und berechnet den laufenden Saldo je Ursprungskonto aus
Eröffnungssaldo, realen und erwarteten Buchungen; Stornos verändern ihn
nicht.

Sobald Konten oder Inhalte gefiltert sind, kennzeichnet die Statusleiste die
währungsgetrennte Bewegungssumme ausdrücklich als „kein Kontostand“.
Umbuchungen und Stornos zählen nicht in diese Summe. Mehrere persistente
Buchungen lassen sich gemeinsam kategorisieren; nur errechnete
Zukunftsvorgänge bleiben gegen eine solche Änderung geschützt. Kontenauswahl,
Filter, Zukunftsschalter, Zeilenmodus und Spalten können als benannte Ansicht
gespeichert werden. Systemdruck und mehrseitiger PDF-Export verwenden exakt
die sichtbaren Zeilen und Spalten einschließlich Zukunftsvorgängen.

`Zweite Ansicht` teilt den Arbeitsbereich in zwei gleichzeitig sichtbare
Sammelkontoblätter. Ansicht B besitzt eine eigene persistente Kontenkombination,
eigene Status-, Kategorie- und Zeitraumfilter sowie einen eigenen
Zukunftsschalter; globale Volltextsuche und Ein-/Zweizeilenmodus bleiben
bewusst gemeinsam. Beide Seiten zeigen Konto, Betrag und echten laufenden
Saldo, ohne gefilterte Bewegungssummen als Kontostand auszugeben.

Das Menü `Bericht` öffnet die Berichtswerkstatt wahlweise für exakt alle
sichtbaren Buchungen – einschließlich errechneter Zukunft – oder für den
Empfänger, die Kategorie beziehungsweise Klasse/Tag der markierten Buchung.
Die Werkstatt kennzeichnet diese Direktauswahl und lässt sie ausdrücklich
lösen. Exakte Empfängervergleiche sind großschreibungs- und
diakritikaunabhängig; alte Berichtsvorlagen bleiben kompatibel.

## Kategorien und Mehrwertsteuer

Kategorien besitzen neben einer beliebig tiefen Hierarchie eine Beschreibung,
Budgetierbarkeit, einen optionalen Standard-MwSt.-Schlüssel, eine deutsche
Steuerzuordnung und eine optionale US-Steuerzeile. MwSt.-Schlüssel werden
unter `Einstellungen › MwSt.-Schlüssel` frei definiert; auch mehrere
inhaltlich verschiedene Schlüssel mit 0 % bleiben eigenständige Datensätze.

Bei normalen Buchungen kann die Steuer automatisch aus dem Bruttobetrag oder
über einen ausdrücklich eingegebenen Steuerbetrag ermittelt werden. Der
Editor zeigt Brutto, Netto und Steuer vor dem Speichern. Splitzeilen besitzen
jeweils ihren eigenen Schlüssel und Modus; gerundet wird centgenau pro Zeile,
anschließend werden Netto und Steuer zum Beleg addiert. Ein
Kategorie-Standard wird beim Auswählen vorgeschlagen und kann je Buchung oder
Splitzeile überschrieben werden.

## Kontoabgleich

Der Abgleich zeigt den Anfangssaldo aus dem jüngsten aktiven Abgleich oder
dem Eröffnungssaldo und lässt die tatsächlich auf dem Bankauszug enthaltenen
Buchungen einzeln markieren. Anfangssaldo, markierte Summe, berechneter Saldo,
Auszugsendsaldo und Differenz bleiben gleichzeitig sichtbar. Nur markierte
Buchungen werden geschützt; spätere oder nicht ausgewählte Buchungen bleiben
unverändert.

Eine Differenz verhindert den Abschluss. Sie kann nur nach ausdrücklicher
zweiter Bestätigung als auditierte Buchung mit Referenz `ABGLEICH`
ausgeglichen werden. Der jeweils jüngste aktive Abgleich kann zurückgenommen
werden: Ursprüngliche Buchungsstatus werden wiederhergestellt und eine
Ausgleichsbuchung wird storniert, aber nicht gelöscht.

## Berichtswerkstatt

Die Berichtswerkstatt wertet Buchungen als unveränderliche Live-Momentaufnahme
aus. Filter kombinieren Zeitraum, Konten und Gruppen, Kategorieunterbäume,
Klassen/Tags, Empfänger, Status, Betragsspanne, Volltext und Währung.
Ausgeblendete Konten, von Berichten ausgeschlossene Konten, Umbuchungen und
die Einzelauflösung von Splits sind explizite Optionen. Gruppiert wird nach
Kategorie, Empfänger, Konto oder Klasse/Tag; optional teilt eine zweite,
abweichende Dimension jede Primärgruppe weiter auf. Kombinierte Bezeichnungen
wie `Kategorie › Konto` bleiben in Tabelle, Drill-down, CSV, PDF und Druck
identisch. Jede Gruppe besitzt einen Drill-down bis zu ihren Buchungen und
Splitzeilen. Währungen werden niemals
unbemerkt addiert. Filter, Gruppierung und Sortierung lassen sich als
versionierte Vorlage speichern. Das Menü `Standardberichte` setzt sechs
sofort nutzbare, weiterhin vollständig editierbare Abfragen für
Einnahmen/Ausgaben nach Kategorie oder Empfänger, Buchungsbericht, Cashflow,
Kontobewegungen sowie Kategorie/Klasse auf. Sie beginnen im aktuellen
Kalenderjahr und verwenden dieselbe Snapshot-, Drill-down- und Exportlogik wie
freie Berichte. CSV-Ausgaben unterstützen Semikolon, Komma
oder Tabulator sowie UTF-8 oder ISO-8859-1 und verwenden ein deterministisches
deutsches Zahlenformat. Druckfertige PDF-Berichte entstehen wahlweise als
A4-Hoch- oder Querformat mit Titel, Zeitraum, Filterbeschreibung,
Basiswährung, wiederholten Tabellenköpfen und Seitenzahlen. Dieselbe aktuelle
Momentaufnahme kann entweder als PDF gespeichert oder direkt über den
macOS-Systemdruckdialog ausgegeben werden.

Der Standardbericht `Kontosalden und Nettovermögen` besitzt eine eigene
Stichtagsberechnung: Eröffnungssaldo und alle nicht stornierten Buchungen bis
zum Tagesende ergeben für jedes Konto den historischen Saldo. Konto,
Kontengruppe, Währung sowie ausgeblendete, geschlossene oder vom
Nettovermögen ausgeschlossene Konten sind filterbar. Eröffnung, Bewegungen
und Saldo stehen nebeneinander; Aktiva, Passiva und Nettovermögen werden je
Währung getrennt summiert. Die gleiche Momentaufnahme speist Bildschirm,
deterministisches CSV, mehrseitiges A4-PDF und direkten Systemdruck.

`Zeitvergleich` stellt zwei frei wählbare Zeiträume gegenüber. Als Kennzahl
stehen Einnahmen, Ausgaben oder Saldo bereit; gruppiert wird nach Kategorie,
Empfänger, Konto, Klasse/Tag oder gar nicht. Der Vergleich kann als Summe oder
als Monatsdurchschnitt berechnet werden. Betrag, Abweichung und prozentuale
Änderung werden einschließlich währungsgetrennter Gesamtsummen angezeigt,
und beide Zeiträume besitzen einen eigenen Buchungs-Drill-down.

`Budget Plan/Ist/Abweichung` wertet ein vorhandenes Budget über dessen
zwölfmonatiges Geschäftsjahr oder einen einzelnen Monat aus. Es berücksichtigt
nur offene, budgetfähige Konten in der Budgetwährung und löst Splitbuchungen
ohne Doppelzählung auf. Vollständige Kategoriepfade, Einnahmen-/Ausgabenart,
Plan, Ist, Abweichung und Zielerreichung bleiben in Bildschirm, CSV,
mehrseitigem PDF und direktem Druck identisch.

## Zahlungsverkehr

Der Zahlungsverkehr ist ausdrücklich ein lokaler Simulator ohne echte
Bankverbindung. Überweisungsentwürfe prüfen Empfänger, positiven Betrag und
IBAN, zeigen vor der simulierten Übermittlung eine unveränderliche
Zusammenfassung und speichern keine TAN oder Freigabecodes. Angenommene
Aufträge werden idempotent als vorgemerkte Buchung materialisiert.

Ein einzelner Auftrag kann als `pain.001.001.09`-XML exportiert werden. Der
Writer verwendet das datierte Regelpaket `EPC-SCT-2025-V1.0`, schreibt
Kontrollsummen, `SLEV`, Ausführungsdatum und bei Echtzeitüberweisungen
`INST`. Vor dem Export werden Auftraggebername und -IBAN, EUR-Währung,
BIC-Format, EPC-Längen sowie die Slash-Regeln für Kennungen geprüft. Ohne
BIC des Auftraggeberinstituts wird regelkonform `NOTPROVIDED` geschrieben.
Nur unveränderte Entwürfe können initiiert werden; terminale oder bereits
übermittelte Aufträge sind gegen erneuten Export gesperrt. Die Funktion sendet
die Datei nicht und behauptet keine bankseitige Annahme.

Daueraufträge besitzen eine eigene, lokale Verwaltung mit Empfänger,
IBAN/BIC, Betrag, Rhythmus, optionalem Enddatum, Verschiebungsregel und
versioniertem Bankkalender. `TARGET-Euro-Kalender v1` berücksichtigt neben
Wochenenden Neujahr, Karfreitag, Ostermontag, den 1. Mai sowie den 25. und
26. Dezember; das bisherige reine Montag-bis-Freitag-Verhalten bleibt als
explizites Profil verfügbar. Kalenderkennung und Version werden im Auftrag
und in jeder Ausführungshistorie gespeichert. Sie
können pausiert, fortgesetzt oder endgültig beendet werden. Eine Fälligkeit
wird nur nach Bestätigung als einzelner Terminüberweisungsentwurf
materialisiert oder dauerhaft übersprungen. Die eindeutige Kombination aus
Dauerauftrag und Fälligkeitsdatum sowie eine unveränderliche Historie
verhindern Doppelentwürfe; spätere Vorlagenänderungen verändern bereits
erzeugte Aufträge nicht.

Überweisungs- und Lastschriftentwürfe warnen sichtbar vor einem gewählten
TARGET-Schließtag, bleiben aber bewusst editierbare lokale Entwürfe.
Echtzeitüberweisungen werden getrennt als 24/7-Verfahren gekennzeichnet. Die
Kalenderregeln folgen dem aktuellen Merkblatt der Deutschen Bundesbank und
dem TARGET-Betriebskalender der EZB; eine spätere Regeländerung erhält eine
neue Profilkennung statt bestehende Historie umzudeuten.

SEPA-Core-Lastschriften verwenden ein offenes EUR-Gläubigerkonto, eine
aktive Empfänger-Bankverbindung und ein aktives unterschriebenes Mandat.
Gläubiger- und Schuldnerdaten, Mandatsreferenz, Unterschriftsdatum,
Sequenztyp, Fälligkeit, Betrag, Verwendungszweck und End-to-End-ID werden beim
Anlegen unveränderlich eingefroren. Nach doppelter Bestätigung durchläuft der
lokale Simulator dieselbe sichere Statusmaschine; eine Annahme erzeugt genau
eine vorgemerkte Gutschrift. Entwürfe können lokal als
`pain.008.001.08` nach dem datierten Regelpaket `EPC-SDD-CORE-2025-V1.1`
exportiert werden. Es findet keine echte Bankübermittlung statt.

Mehrere kompatible Entwürfe lassen sich als unveränderlicher
Sammelzahlungsauftrag bündeln. Sammelüberweisungen verlangen dasselbe offene
EUR-Auftraggeberkonto, denselben Ausführungstag und denselben Auftragstyp;
Sammellastschriften zusätzlich dieselbe Gläubigeridentität, Sequenz und
Fälligkeit. Die Detailansicht zeigt Anzahl, Gesamtsumme und alle Positionen
vor der doppelten Bestätigung. Statusübergänge und die genau-einmalige
Erzeugung vorgemerkter Buchungen erfolgen für den gesamten Sammler atomar;
Einzelaktionen auf enthaltenen Aufträgen sind gesperrt. Der lokale Export
schreibt ein gemeinsames `pain.001.001.09` beziehungsweise
`pain.008.001.08` mit `BtchBookg`, Kontrollsumme und allen Positionen und
sendet weiterhin keine Daten an eine Bank.

Bankseitige Zahlungsstatusberichte können lokal als streng geprüftes
`pain.002.001.10` importiert werden. Vor dem Commit zeigt FinanzVerwalter jede
unveränderliche Originalreferenz, den Bankstatus, Ablehnungsgründe, die exakt
zugeordnete lokale Zahlung und den möglichen Statuswechsel. Nur `ACSC` und
`RJCT` dürfen einen eingereichten Einzel- oder Sammelauftrag finalisieren;
Zwischenstände wie `ACTC`, `ACCP`, `ACSP`, `PDNG` oder `PART` werden nur in der
Historie gespeichert. Ein angenommenes Sammelpaket wird samt Mitgliedern und
Buchungen in einer SQLite-Transaktion abgeschlossen. Dateifingerabdrücke
verhindern Doppelimporte; XML-DTDs, externe Entitäten, falsche Namespaces und
veraltete Vorschauen werden abgewiesen.

## Dokumentation

- [Gedächtnis.md](Gedächtnis.md) – verifizierter Arbeits- und Teststand
- [PortalPrompt.md](PortalPrompt.md) – reproduzierbare Bauanweisung
- [Anforderungsmatrix](docs/Anforderungsmatrix.md) – ehrliche Soll-Ist-Prüfung
- [Berichtswerkstatt](docs/Berichtswerkstatt.md) – recherchierter Sollentwurf
- [Architekturentscheidungen](docs/adr/) – begründete technische Leitplanken

## Kompatibilität und Markenhinweis

**FinanzVerwalter** ist eine unabhängige Neuentwicklung. Das Projekt steht in
keiner Verbindung zu den Herstellern oder Rechteinhabern von Quicken oder
Lexware FinanzManager und wird von ihnen weder unterstützt noch autorisiert.

Fremde Produktbezeichnungen werden ausschließlich sachlich verwendet, wenn
dies zur Beschreibung von Import-, Export- oder Dateikompatibilität
erforderlich ist, zum Beispiel „Import von Quicken-QIF-Dateien“. Sie sind
keine Produktnamen dieses Projekts. Maßgebliche Leitplanke ist
[§ 23 MarkenG](https://www.gesetze-im-internet.de/markeng/__23.html),
insbesondere die Pflicht zu anständigen Gepflogenheiten nach Absatz 2.

Es werden keine proprietären Originalassets und kein fremder Quellcode
verwendet. Dieser Hinweis ist keine Rechtsberatung.
