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

Reale Finanzexporte gehören nicht in das Repository; `.gitignore` schließt
QIF-, OFX- und QFX-Dateien ausdrücklich aus.

## Kontoblatt

Das Kontoblatt filtert nach Konto, Status, vollständigem Kategoriepfad und
Zeitraum. Mehrere Buchungen können ausgewählt und nach einer Vorschau mit
währungsgetrennten Summen gemeinsam kategorisiert werden. Die Änderung läuft
atomar; enthält die Auswahl abgeglichene Buchungen, Umbuchungen oder
Splitbuchungen, wird sie vollständig abgewiesen. Kategoriepfade erscheinen
einzeilig mit mittiger Kürzung und vollständig im Tooltip.

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
einmalig auch in vorhandene Spalteneinstellungen aufgenommen; anschließend
bleibt sie wie jede andere Spalte frei schaltbar. Das Menü `Ausgabe` druckt
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
Kategorie, Empfänger, Konto oder Klasse/Tag; jede Gruppe besitzt einen
Drill-down bis zu ihren Buchungen und Splitzeilen. Währungen werden niemals
unbemerkt addiert. Filter, Gruppierung und Sortierung lassen sich als
versionierte Vorlage speichern. CSV-Ausgaben unterstützen Semikolon, Komma
oder Tabulator sowie UTF-8 oder ISO-8859-1 und verwenden ein deterministisches
deutsches Zahlenformat. Druckfertige PDF-Berichte entstehen wahlweise als
A4-Hoch- oder Querformat mit Titel, Zeitraum, Filterbeschreibung,
Basiswährung, wiederholten Tabellenköpfen und Seitenzahlen.

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
IBAN/BIC, Betrag, Rhythmus, optionalem Enddatum und Wochenendregel. Sie
können pausiert, fortgesetzt oder endgültig beendet werden. Eine Fälligkeit
wird nur nach Bestätigung als einzelner Terminüberweisungsentwurf
materialisiert oder dauerhaft übersprungen. Die eindeutige Kombination aus
Dauerauftrag und Fälligkeitsdatum sowie eine unveränderliche Historie
verhindern Doppelentwürfe; spätere Vorlagenänderungen verändern bereits
erzeugte Aufträge nicht.

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
