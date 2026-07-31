# FinanzVerwalter – eigenständige Desktop-Finanzverwaltung

Native, local-first macOS-App für private Finanzverwaltung. Das Projekt ist
eine vollständige Neuentwicklung und verwendet keine Quellteile aus anderen
Apps im Workspace.

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

Reale Finanzexporte gehören nicht in das Repository; `.gitignore` schließt
QIF-, OFX- und QFX-Dateien ausdrücklich aus.

## Dokumentation

- [Gedächtnis.md](Gedächtnis.md) – verifizierter Arbeits- und Teststand
- [PortalPrompt.md](PortalPrompt.md) – reproduzierbare Bauanweisung

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
