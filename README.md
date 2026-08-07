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

Ein größerer deterministischer Kontenblatt-Referenzfall lässt sich ohne
private Quelldatei mit `-reference-demo` starten. Er erzeugt in einer
temporären Finanzdatei 12 Konten in vier Gruppen, 10.000 Buchungen über zehn
Jahre, 200 Splitzeilen, 150 Umbuchungen und EUR/USD/CHF. Die temporäre Datei
wird weder zur normalen Finanzdatei noch zum Repository hinzugefügt.

Der normale Start verwendet die lokale Finanzdatei:

`~/Library/Application Support/FinanzVerwalter/Meine Finanzen.qdata`

Über `Ablage › Neue Finanzdatei …` (`⇧⌘N`) und
`Ablage › Finanzdatei öffnen …` (`⌘O`) können mehrere vollständig getrennte
`.qdata`-Dateien geführt werden. Vor jedem Wechsel sichert FinanzVerwalter die
aktuelle Datei per SQLite-Online-Backup, schließt offene Editoren und lädt den
neuen Datenbestand vollständig. Das Menü „Zuletzt verwendete Finanzdateien“
merkt höchstens zehn vorhandene Dateien; beim nächsten normalen Start wird die
zuletzt verwendete reguläre Datei geöffnet. Symlinks, falsche Dateiendungen,
beschädigte Dateien und vorhandene Ziele beim Neuanlegen werden abgewiesen.

Weitere Ablagebefehle schließen die aktive Datei erst nach einer erzwungenen
Sicherung, erstellen eine unabhängige geprüfte Kopie mit privaten
Dateirechten (`0600`) oder schreiben einen archivierten SQLite-Snapshot mit
Endung `.qarchive`, SHA-256-Nachweis und Schreibschutz (`0400`). Kopie und
Archiv entstehen zunächst als zufällig benannte Zwischenkopie im Zielordner;
erst nach Integritäts-, Größen- und Hashprüfung werden sie atomar an den
endgültigen Namen verschoben. Vorhandene Ziele werden niemals überschrieben.

Der opt-in-Leistungstest erweitert denselben Datensatz auf 100.000 Buchungen.
Lege dafür ausschließlich für den Test die Datei
`/tmp/finanzverwalter-run-large-performance-tests` an und starte gezielt
`testHundredThousandBookingReferencePerformanceTargets`; entferne die Datei
danach wieder. Der normale Testlauf überspringt diesen ressourcenintensiven
Fall. Die Grenzwerte sind 30 s Persistierung, 3 s vollständig geladener
Startkern, 500 ms Kontenblattberechnung und 2 s Standardbericht.

## Kontenübersicht

Die Kontenübersicht zeigt Gruppenzuordnung, Kontoart, Währung, Saldo,
verfügbaren Betrag, Abrufstatus und letzten Abruf. Toolbar und Kontextmenü
führen das gewählte Konto direkt zum Kontoblatt, schreibgeschützten
Banking-Abruf oder Abgleich. Konten lassen sich ausblenden, schließen und
wieder öffnen. Vor dem bestätigten Schließen werden der aktuelle Saldo und
verknüpfte aktive Serien-, Dauer- und offene Zahlungsaufträge genannt;
vorhandene Buchungen bleiben erhalten.

Schema 39 ergänzt die vollständigen Kontostammdaten um einen frei
bezeichenbaren Untertyp, eine validierte achtstellige deutsche BLZ, einen vom
Eröffnungsdatum unabhängigen Stichtag des Eröffnungssaldos, ein optionales
Schließdatum und ein zugeordnetes Verrechnungs-, Anlage-, Darlehens- oder
Gegenkonto. Das Gegenkonto muss vorhanden und vom bearbeiteten Konto
verschieden sein. Schließen setzt im direkten Übersichtsablauf den heutigen
Tag; Wiederöffnen entfernt das Schließdatum.

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
Splits, Tags und vorhandene Fremdwährungsangaben, aber niemals altes Datum,
Belegnummer, Transfer- oder Importidentität. Eine einzelne Umbuchungsseite ist
keine zulässige Vorlage.

Über das Kontextmenü `Als regelmäßigen Vorgang …` entsteht aus genau einer
markierten Buchung unmittelbar ein vorausgefüllter Serienentwurf. Die nächste
monatliche Fälligkeit behält den Buchungstag beziehungsweise die
Monatsende-Semantik. Schema 38 speichert zusätzlich den vollständigen
Buchungsinhalt: Notiz, Empfängerakte, Tags, Splits samt Split-Tags und MwSt.
sowie Originalbetrag und Wechselkurs. Bank-, Import-, Abgleichs- und
Umbuchungsidentitäten werden nicht kopiert. Bei strukturierten Beträgen bleibt
das Betragsfeld im Serieneditor geschützt, damit Aufteilung, Steuer und
Fremdwährung nicht auseinanderlaufen. Eine bewusst abweichende einzelne oder
künftige Serieninstanz wird als einfache Buchung erzeugt und übernimmt keine
dadurch unzutreffenden Splits oder Währungsdaten.

## Betragsrechner im Buchungsdialog

Das Betragsfeld wertet neben deutschen Beträgen auch die Grundrechenarten
`+`, `−`, `×`, `÷`, die Tastaturzeichen `-`, `*`, `/` und Klammern aus. Eine
optionale führende `=` ist erlaubt. Beispielsweise wird
`=(1.234,56 + 5,44) / 2` exakt zu `620,00 €` ausgewertet. Multiplikation und
Division haben Vorrang; Zwischenergebnisse verwenden ausschließlich
`Decimal`, die Rundung auf die Nachkommastellen der Kontowährung erfolgt erst
am Ende.

Dieselbe Eingabe gilt für Originalbeträge in Fremdwährung, Splitzeilen und
manuelle Steuerbeträge. Der Split-Restbetrag bezieht sich auf die bereits
ausgewerteten Zeilen. Division durch null, unvollständige oder übergroße
Ausdrücke und ungültige deutsche Zahlengruppierung werden ohne Teilbuchung
abgewiesen.

## Fremdwährungen

Jede Buchung bleibt zwingend in der Währung ihres Kontos. Bei einem Beleg in
einer anderen Währung speichert FinanzVerwalter zusätzlich Originalbetrag,
dreistelligen ISO-Code und den daraus abgeleiteten Kurs mit acht festen
Dezimalstellen. Die Umrechnung verwendet ausschließlich `Decimal` und
kaufmännisch symmetrische Banker's-Rundung; JPY, KWD und andere Währungen
verwenden ihre vom System gemeldete Anzahl an Nachkommastellen.

Bei einer Umbuchung zwischen unterschiedlichen Währungen werden Abgang und
Gutschrift getrennt eingegeben. Beide Kontoseiten entstehen atomar mit ihrer
jeweiligen Kontowährung, gegenseitigem Originalbetrag und reproduzierbarem
Kurs. In der zweizeiligen Kontoblattansicht steht der Originalbetrag direkt
unter dem gebuchten Betrag. Summen und Salden bleiben immer nach Währung
getrennt; ohne explizite Umrechnungsregel werden verschiedene Währungen nicht
addiert.

## Beleganhänge an Buchungen

Bei einer bereits gespeicherten Buchung verwaltet der Buchungseditor mehrere
lokale Anhänge. Dateien können über `Datei hinzufügen …` oder per Drag-and-drop
in den Abschnitt `Anhänge` übernommen werden. Zugelassen sind PDF, PNG, JPEG,
TXT, CSV, QIF und XML bis jeweils 50 MB. Erweiterung und Dateisignatur
beziehungsweise UTF-8-Inhalt werden vor jeder Ablage geprüft; symbolische
Links, leere Dateien, ausführbare Typen und während des Lesens veränderte
Dateien werden abgewiesen.

Schema 32 speichert den Originalinhalt atomar und SHA-256-adressiert direkt in
der Finanzdatei. Identische Inhalte belegen deshalb auch bei mehreren
Buchungen nur einmal Speicher, während jede Verknüpfung ihren ursprünglichen
Dateinamen, MIME-Typ, Größe, Quelle und Hinzufügezeitpunkt bewahrt. Dadurch
enthalten manuelle und automatische SQLite-Sicherungen auch alle Belege. Vor
dem Öffnen verlangt die Oberfläche eine Bestätigung, prüft Größe und SHA-256
erneut und erzeugt erst dann eine nur für den Benutzer les- und schreibbare
lokale Vorschau. Ein injizierbarer Scan-Hook kann den Import vor dem Commit
abbrechen.

Dieselbe Anhangsoberfläche steht außerdem im Editor eines bestehenden Kontos
und in den Detailakten von Verträgen, Wertpapieren und Inventargegenständen
bereit. Ein identischer Originalbeleg wird auch über diese verschiedenen
Fachakten hinweg nur einmal gespeichert. Jeder Bereich besitzt einen stabilen
Accessibility-Bezeichner und semantisch beschriftete Öffnen-, Exportieren- und
Entfernen-Aktionen. Der offene Export verwendet den Originaldateinamen im
System-Speicherdialog, prüft den gespeicherten BLOB vor dem Schreiben erneut,
schreibt über eine private 0600-Staging-Datei und ersetzt weder Dateien noch
Symlinks ohne die ausdrückliche Systembestätigung. Dateiendung, Größe und
SHA-256 werden auch am fertigen Exportziel geprüft.

Beim Undo einer neu angelegten Buchung werden ihre Anhänge und nicht mehr
referenzierte Inhalte gemeinsam entfernt. Wird eine gelöschte Buchung
zurückgeholt, bleibt ihre Belegverknüpfung erhalten.

Notizen in Buchungen, Konto-Beschreibungen, Verträgen, Wertpapieren und
Inventargegenständen erkennen jetzt lokale `file:`-Links und HTTPS-Adressen.
Sie öffnen niemals beim Anzeigen oder Bearbeiten. Jede Aktion verlangt eine
eigene Bestätigung und validiert das Ziel unmittelbar danach erneut. Weblinks
brauchen HTTPS, einen Host und dürfen keine eingebetteten Zugangsdaten tragen;
lokale Ziele müssen vorhandene reguläre Dateien sein. Symlinks, Pakete,
Verzeichnisse, ausführbare Rechte und bekannte Skript-/Programmendungen werden
blockiert. OCR bleibt als optionaler Adapter noch offen.

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

Die einblendbare `Schnellbuchung` erfasst normale Buchungen direkt oberhalb
der Tabelle: Datum, offenes Konto, Empfänger, Verwendungszweck, vollständiger
Kategoriepfad, Status und Betrag bleiben in einer kompakten, horizontal
scrollbaren Buchungszeile. Das Betragsfeld verwendet denselben exakten
Decimal-Rechner wie der vollständige Dialog. Eingabe im Betragsfeld speichert,
Esc leert den Entwurf und Tab wechselt zwischen den Feldern. Nach erfolgreichem
Speichern bleiben Datum und Konto für die nächste Eingabe stehen; alle
fachlichen Inhaltsfelder werden geleert und der Fokus kehrt zum Empfänger
zurück. Die Buchung läuft durch denselben validierten, auditierten und
konfliktgeschützt rückgängig machbaren Store-Pfad. Split, Umbuchung,
Fremdwährung, MwSt., Klassen und Anhänge bleiben bewusst im vollständigen
Buchungsdialog.

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

Nach Erstellen, Bearbeiten, Verschieben, gemeinsamer Kategorie-/Klassen-
Änderung, Löschen oder Erstellen einer Umbuchung erscheint im Kontoblatt
`Rückgängig`. FinanzVerwalter speichert dafür vor und nach der Änderung einen
vollständigen, persistenten Buchungssnapshot. Ein Löschvorgang oder eine
Umbuchung wird immer als gesamtes Paket wiederhergestellt. Vor dem Undo wird
der aktuelle Zustand exakt mit dem erwarteten Nachher-Snapshot verglichen;
fehlt eine Buchung, wurde sie erneut geändert oder ist sie inzwischen
abgeglichen, wird keine einzige Teiländerung ausgeführt. Erfolgreiche Undo-
Pakete sind einmalig und auditierbar.

Direkt rechts neben dem Betrag steht der kontenweise laufende Saldo. Die
Darstellung kann dauerhaft zwischen einer kompakten Einzeile und einer
zweizeiligen Ansicht mit Wertstellung, Memo, Referenz und Tags umgeschaltet
werden. Bestands- und QIF-Konten werden in Bankkonten, Kreditkarten, Bargeld,
Depots, Kredite, Vermögen, Verbindlichkeiten, Forderungen oder Sonstige
einsortiert. Datum, Wertstellung, Belegnummer, Status, Empfänger,
Verwendungszweck, Kategorie, Klasse/Tags, Konto, Betrag und Saldo lassen sich
vollständig ein- oder ausblenden. Benannte Ansichten speichern Konto, Filter,
Zeitraum, Zeilenmodus, Sortierung und Spaltenauswahl und können später wieder
geladen oder gelöscht werden. Das Menü `Sortierung` ordnet auf- oder
absteigend nach jeder Standardspalte; alternativ lässt sich der jeweilige
Spaltenkopf direkt anklicken und ein erneuter Klick kehrt die Richtung um:
Datum, Wertstellung, Belegnummer,
Status, Empfänger, Zweck, vollständigem Kategoriepfad, Klassen/Tags, Konto,
Betrag oder Saldo. Deutsche Texte werden diakritikaunabhängig und natürlich
numerisch sortiert; gleiche Werte sind über Datum und Buchungs-UUID stabil.
Der angezeigte Saldo bleibt immer der historisch-chronologische Saldo genau
dieser Buchung und wird durch eine andere Zeilenreihenfolge nicht verfälscht.
Der native macOS-Tabellenkopf zeigt die aktive Richtung und stellt dieselbe
Sortieraktion über Tastatur und VoiceOver bereit.
Ein weiteres Ansichtsmenü schaltet die einzelne Spalte `Betrag` auf zwei
getrennte Spalten `Soll` und `Haben` um. Negative Bewegungen erscheinen ohne
Minuszeichen als positiver Betrag unter Soll, positive unter Haben und Null
bleibt in beiden Spalten leer. Einzel-, Zweit- und Sammelkontoblatt sowie
Sortierung, gespeicherte Ansichten, PDF, Druck und CSV verwenden denselben
Modus; die zugrunde liegende vorzeichenbehaftete Buchung wird nie verändert.
Beim ersten Start nach dem Saldo-Update wird die Spalte
einmalig auch in vorhandene Spalteneinstellungen und benannte Ansichten
aufgenommen; anschließend bleibt sie wie jede andere Spalte frei schaltbar.
Das Menü `Ausgabe` druckt das gefilterte Kontoblatt direkt über den
macOS-Druckdialog oder exportiert es als mehrseitiges PDF beziehungsweise CSV.
Dabei werden exakt die sichtbaren Spalten und Zeilen aus derselben
unveränderlichen Momentaufnahme verwendet. CSV enthält Titel, Filter und
Erstellzeit und ist als Semikolon/UTF-8, Komma/UTF-8 oder
Semikolon/Windows-1252 wählbar. Trennzeichen, Anführungszeichen und
Zeilenumbrüche werden verlustfrei maskiert; ein im gewählten Encoding nicht
darstellbares Zeichen bricht den Export statt stiller Ersetzung ab. PDF
wiederholt Tabellenköpfe, Filterbeschreibung und Seitenzahlen.

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

Die globale Kontenblattsuche verwendet in Einzel-, geteilter und
Sammelansicht denselben vorberechneten Volltextindex. Mehrere Suchwörter
müssen gemeinsam vorkommen, dürfen aber aus unterschiedlichen Feldern
stammen. Durchsucht werden unter anderem alle Konto- und Bankangaben,
Empfänger, Zweck, Memo, Referenz, vollständige Kategorie- und Klassenpfade,
Status, Buchungs- und Wertstellungstag, Beträge, laufender Saldo sowie
Bankreferenzen. Groß-/Kleinschreibung und Diakritika spielen keine Rolle;
auch Wortteiltreffer wie `steuer` in `Grundsteuer` bleiben möglich.

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
gespeichert werden. Systemdruck, mehrseitiger PDF- und wählbarer CSV-Export
verwenden exakt die sichtbaren Zeilen und Spalten einschließlich
Zukunftsvorgängen.

Direkt über der Tabelle zeigt jede Währung ihren eigenen Tagesverlauf. Ohne
Filter beginnt er bei der Summe der Eröffnungssalden und zeigt den echten
aggregierten Kontostand nach der letzten Buchung jedes Tages. Mit irgendeiner
inhaltlichen oder Kontenauswahl wird er orange als kumulierte gefilterte
Bewegungssumme bezeichnet; Eröffnungssalden, Stornos und Umbuchungen fließen
dann nicht ein. Bei weniger als 30 Tageswerten erscheinen sichtbare Punkte.
Das Verweilen über einem Tag markiert in der Tabelle dessen letzte Buchung.

`Zweite Ansicht` teilt den Arbeitsbereich in zwei gleichzeitig sichtbare
Sammelkontoblätter. Ansicht B besitzt eine eigene persistente Kontenkombination,
eigene Status-, Kategorie- und Zeitraumfilter sowie einen eigenen
Zukunftsschalter; globale Volltextsuche und Ein-/Zweizeilenmodus bleiben
bewusst gemeinsam. Beide Seiten zeigen Konto, Betrag, echten laufenden Saldo
und denselben währungsgetrennten Tagesverlauf, ohne gefilterte
Bewegungssummen als Kontostand auszugeben.

Das Menü `Bericht` öffnet die Berichtswerkstatt wahlweise für exakt alle
sichtbaren Buchungen – einschließlich errechneter Zukunft – oder für den
Empfänger, die Kategorie beziehungsweise Klasse/Tag der markierten Buchung.
Die Werkstatt kennzeichnet diese Direktauswahl und lässt sie ausdrücklich
lösen. Exakte Empfängervergleiche sind großschreibungs- und
diakritikaunabhängig; alte Berichtsvorlagen bleiben kompatibel.

## Kalender und Prognose

Der Kalender erzeugt aus persistenten regelmäßigen Vorgängen eine
30-, 90-, 180- oder 365-Tage-Prognose. Monatsbasierte Serien bewahren ihre
Monatsende-Semantik. Der prognostizierte Saldo beginnt beim realen Bestand
und berücksichtigt anschließend erwartete Buchungen sowie noch nicht
materialisierte Serientermine.

Die Ansicht lässt sich zwischen Liste, Monat und Woche umschalten. Monat und
Woche beginnen am Montag, füllen Randtage vollständig auf und bleiben über
Schaltmonat und Jahreswechsel korrekt. Gebuchte, vorgemerkte, erwartete,
regelmäßige und stornierte Vorgänge besitzen eine eigene Farbe samt Legende.
Konto, vollständiger Kategoriepfad und vollständiger Klassen-/Tag-Pfad sind
kombinierbar filterbar; bei einem Oberknoten werden seine Unterkategorien oder
Unterklassen mit einbezogen. Kategorien und Klassen in Splitzeilen zählen
ebenfalls. `Heute` und die Pfeiltasten navigieren deterministisch durch den
gewählten Zeitraum.

Erwartete manuelle Prognosebuchungen und regelmäßige Termine lassen sich in
Monat und Woche auf einen anderen Tag ziehen. Vor dem Speichern zeigt die App
Quell- und Zieldatum zur Bestätigung. Vergangenheit, derselbe Tag, gebuchte
Vorgänge und verknüpfte Umbuchungen werden abgewiesen. Eine reale erwartete
Buchung behält alle Inhalte und wird mit Buchungs-Undo gespeichert; ein
regelmäßiger Termin wird als rücksetzbare Einzelausnahme verschoben und behält
seine stabile Ursprungskennung.

Eine einzelne Serieninstanz kann über ihren stabilen Ursprungstermin
geändert oder übersprungen werden. Datum, Empfänger, Verwendungszweck,
Kategorie und Betrag der geänderten Instanz werden dauerhaft als Ausnahme
gespeichert; ein verschobener Termin behält intern seine ursprüngliche
Identität und wird deshalb weder erneut erzeugt noch doppelt gezählt.
Geänderte und übersprungene Instanzen bleiben in `Serienausnahmen` sichtbar
und können dort auf den Serienwert zurückgesetzt werden. Alternativ lassen
sich Datum, Empfänger, Verwendungszweck, Kategorie und Betrag ab einer
gewählten Instanz für diese und alle folgenden Fälligkeiten ändern. Der
Rhythmus wird dabei vom neuen Datum aus mit derselben Frequenz fortgeführt;
alle virtuellen Termine behalten dennoch ihre stabile ursprüngliche
Herkunftskennung. Solche Änderungspunkte sind als `Serienänderungen`
sichtbar, einzeln rücksetzbar und können weiterhin durch eine spätere
Einzelausnahme übersteuert werden.

Über `Szenarien` öffnet sich eine eigenständige Liquiditätsplanung. Benannte
Was-wäre-wenn-Szenarien und ihre manuellen Positionen werden in der
Finanzdatei gespeichert. Jede Position besitzt Konto, Datum, Bezeichnung,
Betrag, Aktivschalter und Notiz. Die Berechnung ist täglich, wöchentlich oder
monatlich sowie für alle Prognosekonten einer Währung, ein einzelnes Konto
oder eine Kontengruppe verfügbar. Sie zeigt Anfang, Bewegung, Schluss,
Minimum, Maximum und Unterdeckungen sowie den Unterschied zum Basisverlauf.

Jede Zeile nennt ihre Herkunft: gebucht, vorgemerkt, erwartet,
Zahlungsauftrag, Dauerauftrag, regelmäßiger Vorgang oder Szenario. Reale
Buchungen, noch offene Terminüberweisungen, aktive Daueraufträge und
allgemeine Serientermine werden anhand eines starken Schlüssels aus Konto,
Kalendertag, Betrag und normalisierter Bezeichnung priorisiert dedupliziert.
Reale Buchung geht vor Zahlungsauftrag, dieser vor Dauerauftrag und
Serientermin. Explizite Szenarioannahmen bleiben absichtlich additiv. Konten
verschiedener Währungen werden niemals zu einem Prognosesaldo addiert.

## Kategorien und Mehrwertsteuer

Kategorien besitzen neben einer beliebig tiefen Hierarchie eine Beschreibung,
Budgetierbarkeit, einen optionalen Standard-MwSt.-Schlüssel, eine deutsche
Steuerzuordnung und eine optionale US-Steuerzeile. MwSt.-Schlüssel werden
unter `Einstellungen › MwSt.-Schlüssel` frei definiert; auch mehrere
inhaltlich verschiedene Schlüssel mit 0 % bleiben eigenständige Datensätze.

Die Kategorieverwaltung durchsucht Name, vollständigen Hierarchiepfad,
Beschreibung, Art sowie deutsche und US-Steuerzuordnung gemeinsam. Die Suche
ignoriert Groß-/Kleinschreibung und Diakritika, kombiniert mehrere Wörter und
erhält alle benötigten Oberkategorien im Baum. Inaktive Kategorien lassen sich
ausblenden; eine inaktive Oberkategorie bleibt dennoch als notwendiger Pfad zu
einer passenden aktiven Unterkategorie sichtbar. Bei Suchtreffern steht der
vollständige Pfad platzsparend in einer zweiten, einzeilig gekürzten Zeile und
vollständig im Hilfetext.

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
Kategorie, Empfänger, Konto, Klasse/Tag, Monat oder deutscher Steuerzuordnung;
optional teilt eine zweite,
abweichende Dimension jede Primärgruppe weiter auf. Kombinierte Bezeichnungen
wie `Kategorie › Konto` bleiben in Tabelle, Drill-down, CSV, PDF und Druck
identisch. Jede Gruppe besitzt einen Drill-down bis zu ihren Buchungen und
Splitzeilen. Währungen werden niemals unbemerkt addiert. Filter, Gruppierung
und Sortierung lassen sich als versionierte Vorlage speichern.
Buchungsdetails, primäre Zwischensummen und währungsgetrennte Gesamtsummen
sind unabhängig ein- und ausblendbar; diese Darstellungseinstellungen werden
ebenfalls in Vorlagen gespeichert. Das Menü `Standardberichte` setzt acht
sofort nutzbare, weiterhin vollständig editierbare Abfragen für
Einnahmen/Ausgaben nach Kategorie oder Empfänger, Buchungsbericht, Cashflow,
Kontobewegungen, Kategorie/Klasse, monatlichen Cashflow sowie einen deutschen
Steuerbericht auf.
Der Steuerbericht berücksichtigt nur Kategorien mit gepflegter deutscher
Steuerzeile und gliedert darunter nach dem vollständigen Kategoriepfad. Sie beginnen im aktuellen
Kalenderjahr und verwenden dieselbe Snapshot-, Drill-down- und Exportlogik wie
freie Berichte. CSV-Ausgaben unterstützen Semikolon, Komma
oder Tabulator sowie UTF-8 oder ISO-8859-1 und verwenden ein deterministisches
deutsches Zahlenformat. Druckfertige PDF-Berichte entstehen wahlweise als
A4-Hoch- oder Querformat mit Titel, Zeitraum, Filterbeschreibung,
Basiswährung, wiederholten Tabellenköpfen und Seitenzahlen. Dieselbe aktuelle
Momentaufnahme kann entweder als PDF gespeichert oder direkt über den
macOS-Systemdruckdialog ausgegeben werden. Ein druckoptimierter,
deterministischer HTML-Export enthält dieselben Metadaten, Gruppen,
Zwischen-/Gesamtsummen und optionalen Buchungsdetails wie die Oberfläche.
Der XLSX-Export erzeugt ohne zusätzliche Laufzeitabhängigkeit ein echtes
Open-XML-Arbeitsblatt mit numerischen, währungsabhängig formatierten Beträgen.
`Kopieren` legt denselben Bericht gleichzeitig als tabulatorgetrennte Tabelle
und als maskiertes HTML in die macOS-Zwischenablage.

Der eigenständige `Umsatzsteuerbericht` wertet ausschließlich tatsächlich
gespeicherte MwSt.-Angaben aus. Gemischte Belege werden immer je Splitzeile
gerechnet; Brutto, Netto und Steuer stammen dadurch exakt aus der bereits
gerundeten Buchungszeile. Kategoriearten trennen Umsatzsteuer und Vorsteuer,
sodass Erlösgutschriften beziehungsweise Aufwandsrückerstattungen die richtige
Seite mindern. Der Bericht filtert Zeitraum, Konten/-gruppen, Status, Währung
und Kontooptionen, trennt Summen strikt je Währung und zeigt Bruttoumsatz,
Nettoumsatz, Umsatzsteuer, Brutto-/Nettoeinkauf, Vorsteuer und Zahllast je
MwSt.-Schlüssel. Ein Drill-down führt zu den vollständigen Buchungs- und
Splitpositionen; CSV, mehrseitiges PDF und Systemdruck verwenden denselben
Snapshot.

Der eigenständige `Kredit-, Zins- und Tilgungsbericht` verbindet die
hinterlegten Tilgungspläne mit zugeordneten Ist-Zahlungen. Zeitraum, Darlehen,
Währungen und inaktive Darlehen sind filterbar. Übersicht und Raten-Drill-down
zeigen Plan, Ist, Abweichung, Herkunft, Tilgung, Zins, Gebühren,
Sondertilgungen und Restschuld; die Restschuldlinie bleibt der berechnete
Planverlauf. Summen werden streng je Währung geführt. Deterministisches
Semikolon-CSV, mehrseitiges PDF und Systemdruck verwenden denselben Snapshot.

Im Tilgungsplan kann eine vorhandene Belastung des verknüpften Zahlungskontos
zugeordnet oder eine Planrate als neue Buchung erzeugt werden. Schema 37
zerlegt sie atomar in Tilgung, Sollzins, Gebühr und Sondertilgung und schützt
zugeordnete Buchungen vor versehentlicher Änderung. Beim Lösen wird eine
erzeugte Buchung entfernt oder eine vorhandene Buchung exakt auf ihren zuvor
gespeicherten Zustand zurückgesetzt.

Die eigenständige `Vertrags- und Inventarübersicht` verbindet die beiden
Fachakten in einem gemeinsamen, unveränderlichen Snapshot. Vertragstypen,
Inventarkategorien, Aktivstatus, Volltext und Kündigungs-/Garantiehorizonte von
30, 90 oder 365 Tagen sind kombinierbar. Vertragszeilen zeigen Anbieter,
Jahreskosten, nächste Verlängerung, Kündigungsfrist, Zahlungskonto und den
vollständigen Kategoriepfad. Inventarzeilen zeigen Raum, Kaufpreis, aktuellen
Wert, Versicherungswert, Garantie, Händler und Seriennummer. Zeilenauswahl,
deterministisches Semikolon-CSV, PDF und Systemdruck verwenden denselben
Snapshot; die derzeitigen Vertrags- und Inventarwerte sind fachmodellbedingt
EUR-Werte.

Jeder buchungsbasierte Bericht kann zusätzlich als Balken-, Linien-, Flächen-
oder Tortendiagramm für Einnahmen oder Ausgaben dargestellt werden. Die Diagramme
verwenden ausschließlich die bereits gefilterten Detailgruppen desselben
Snapshots. Pro Währung entstehen getrennte Diagramme. Balken und Torte zeigen
die größten elf Werte einzeln und fassen weitere Werte als exakt summierten
Rest zusammen. Linien und Flächen bleiben chronologisch und vollständig, damit
kein Monat im Verlauf verloren geht. Tabelle, Gruppenwahl und Buchungs-Drill-down bleiben darunter
erhalten. Darstellung, Diagrammkennzahl und Steuerfilter werden in
Berichtsvorlagen der Definitionsversion 4 gespeichert; ältere Vorlagen öffnen
weiterhin als Tabelle.

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
Basisplan, Übertrag, verfügbarer Plan, Ist, Abweichung und Zielerreichung
bleiben in Bildschirm, CSV, mehrseitigem PDF und direktem Druck identisch.
Positive Restbeträge und auf Wunsch auch Überschreitungen können monatlich
weitergetragen werden; die Ansicht weist außerdem die Roll-over-Reserve aus.
Über `Jahreswerte` lassen sich alle zwölf Monatswerte einer Kategorie in einem
Schritt bearbeiten. Budgets können umbenannt, vollständig in ein anderes
Geschäftsjahr kopiert, als Folgejahr abgeleitet oder samt ihrer Planzeilen
gelöscht werden; vorhandene Buchungen bleiben beim Löschen unangetastet.

## Freistellungsaufträge

Der eigene Bereich `Freistellungsaufträge` verwaltet Personen, Einzel- und
Gemeinschaftsaufträge, Gültigkeitsjahre, Institute, jährliche Nutzung sowie
die zugehörige Kontenabdeckung. Aus Datenschutzgründen wird nicht die volle
Steuer-ID gespeichert, sondern nur deren letzte vier Ziffern und ein
Bestätigungskennzeichen. Schema 36 hinterlegt versionierte gesetzliche
Regelpakete: 801/1.602 Euro für 2009–2022 und 1.000/2.000 Euro ab 2023 nach
§ 20 Absatz 9 EStG.

Die Regelengine verhindert Überverteilungen, Beträge unterhalb einer bereits
genutzten Freistellung und widersprüchliche gemeinsame Rahmen. Einzelaufträge
beider Partner werden dabei in den gemeinsamen Höchstbetrag eingerechnet.
Konten müssen zum Institut passen; ihre Auswahl dokumentiert nur die
Abdeckung. Der Auftrag gilt weiterhin institutsweit und wird nicht auf
einzelne Konten oder Depots begrenzt. Jahres-, Personen- und Institutsfilter,
Nutzungs-/Restsummen, CSV, mehrseitiges PDF und Systemdruck verwenden denselben
Snapshot. Die Oberfläche verweist auf die amtliche Rechtsgrundlage und
kennzeichnet die Funktion als Verwaltungshilfe, nicht als Steuerberatung.

## Datensicherung und Wiederherstellung

`Import/Export` erstellt manuelle vollständige SQLite-Sicherungen und prüft
sie vor der Ausgabe. Vor einem Restore zeigt eine modale, tastaturbedienbare
Vorschau Dateiname, Finanzdateiname, Basiswährung, Schema, Konten-,
Kategorien- und Buchungszahl, jüngste Buchung, Dateigröße und Dateistand. Sie
liest ausschließlich per SQLite `immutable=1` und akzeptiert nur eine
eigenständig lesbare Datei mit gültigem Finanzdateikopf, kompatiblem Schema
und `integrity_check = ok`; vor dem Austausch entsteht zusätzlich eine
Sicherheitskopie der aktuellen Datei. Abbruch und Abschluss entfernen die
staged Vorschaukopie.

Automatische Sicherungen sind standardmäßig aktiviert. Beim Start und
Beenden wird nur dann eine neue `.qbackup`-Datei im lokalen Unterordner
`Sicherungen` angelegt, wenn sich die Finanzdatei geändert hat und der
konfigurierbare Mindestabstand abgelaufen ist. Unter `Einstellungen >
Automatische Datensicherung` lassen sich Zeitabstand, Höchstzahl und maximales
Alter festlegen oder sofort eine geprüfte Sicherung erzeugen. Standard sind
24 Stunden, 14 Dateien und 90 Tage.

Jede Sicherung wird aus SQLite-WAL vollständig in eine allein nutzbare Datei
checkpointed, unveränderlich geprüft und erst danach freigegeben. Vor einer
Schema-Migration entsteht unabhängig von der Rotation eine eigene Sicherung;
Dateien mit einem neueren unbekannten Schema werden unverändert abgewiesen.
Verschlüsselung, externe Sicherungsziele und der Reparaturmodus auf einer
Kopie sind noch nicht implementiert.

## Zahlungsverkehr

Der Zahlungsverkehr ist ausdrücklich ein lokaler Simulator ohne echte
Bankverbindung. Überweisungsentwürfe prüfen Empfänger, positiven Betrag und
IBAN, zeigen vor der simulierten Übermittlung eine unveränderliche
Zusammenfassung und speichern keine TAN oder Freigabecodes. Angenommene
Aufträge werden idempotent als vorgemerkte Buchung materialisiert.

Solange ein Einzelauftrag noch ein freier Entwurf ist, lässt er sich über
`Entwurf bearbeiten …` vollständig korrigieren. Die Änderung prüft das offene
EUR-Auftraggeberkonto, IBAN, optionale BIC, EPC-Feldlängen, Empfängerakte und
Bankverbindung erneut, berechnet den Idempotenzschlüssel neu und schreibt ein
Auditereignis. Mitglieder eines Sammlers sowie initialisierte oder terminale
Aufträge bleiben unveränderlich. `Entwurf abbrechen …` verlangt eine eigene
Bestätigung, löscht nichts und erhält den Auftrag mit Status und Auditverlauf.

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
TARGET-Schließtag; freie Überweisungsentwürfe bleiben bewusst editierbar.
Echtzeitüberweisungen werden getrennt als 24/7-Verfahren gekennzeichnet. Die
Kalenderregeln folgen dem aktuellen Merkblatt der Deutschen Bundesbank und
dem TARGET-Betriebskalender der EZB; eine spätere Regeländerung erhält eine
neue Profilkennung statt bestehende Historie umzudeuten.

SEPA-Core-Lastschriften verwenden ein offenes EUR-Gläubigerkonto, eine
aktive Empfänger-Bankverbindung und ein aktives unterschriebenes Mandat.
Gläubiger- und Schuldnerdaten, Mandatsreferenz, Unterschriftsdatum,
Sequenztyp, Fälligkeit, Betrag, Verwendungszweck und End-to-End-ID werden beim
Anlegen unveränderlich eingefroren. Dabei werden die EPC-Längen-, BIC- und
Slashregeln bereits vor dem Speichern geprüft. Ein freier oder noch nicht
eingereichter Einzelauftrag kann nach eigener Bestätigung abgebrochen werden;
der unveränderliche Schnappschuss und sein Auditverlauf bleiben erhalten und
es entsteht keine Buchung. Nach doppelter Bestätigung durchläuft der lokale
Simulator dieselbe sichere Statusmaschine; eine Annahme erzeugt genau eine
vorgemerkte Gutschrift. Entwürfe können lokal als
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
sendet weiterhin keine Daten an eine Bank. Ein freier oder noch nicht
eingereichter Sammler lässt sich nur nach Bestätigung abbrechen; Sammler und
alle Mitglieder wechseln atomar nach `cancelled`, bleiben auditiert erhalten
und erzeugen keine Teilbuchung.

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
