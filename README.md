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

### Sicherer Abgleich mit vorhandenen Buchungen

CSV-/TSV- und QIF-Vorschauen vergleichen jede importierte Buchung gestuft mit
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
