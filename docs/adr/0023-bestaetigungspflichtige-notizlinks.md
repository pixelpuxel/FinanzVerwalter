# ADR 0023: Bestätigungspflichtige Notizlinks

## Status

Akzeptiert am 07.08.2026.

## Kontext

Notizen sollen auf lokale Unterlagen und Webseiten verweisen können. Eine
normale SwiftUI-`Link`-Darstellung würde Ziele jedoch direkt an das System
übergeben. Dadurch könnten unsichere URL-Schemata, eingebettete Zugangsdaten,
symbolische Links oder inzwischen durch ausführbare Dateien ersetzte lokale
Ziele ohne erneute fachliche Prüfung geöffnet werden.

## Entscheidung

`SecureNoteLinkPolicy` erkennt Links deterministisch aus dem Notiztext, bietet
aber ausschließlich zwei Zielarten als Aktion an:

- HTTPS mit vorhandenem Host und ohne URL-Benutzer oder -Passwort,
- lokale `file:`-URLs ohne entfernten Host.

Jeder Link erscheint als eigener semantisch beschrifteter Button. Ein Klick
öffnet noch nichts, sondern zeigt zuerst einen Bestätigungsdialog mit dem
benutzersichtbaren Ziel. Erst dessen bewusste Aktion validiert das unveränderte
URL-Ziel unmittelbar erneut. Lokale Ziele müssen zu diesem Zeitpunkt reguläre,
nicht symbolische und nicht ausführbare Dateien sein; Verzeichnisse, Pakete,
ausführbare Rechte und eine konservative Liste bekannter Programm-, Skript-
und Shortcut-Endungen werden abgewiesen. Erst danach darf `NSWorkspace` die
registrierte Anwendung aufrufen.

Die wiederverwendbare `SecureNoteView` wird beim Bearbeiten und Anzeigen von
Buchungsnotizen, Konto-Beschreibungen sowie Vertrags-, Wertpapier- und
Inventarnotizen eingesetzt. Der gespeicherte Freitext bleibt unverändert; es
ist keine Schemaänderung oder automatische Netzwerkanfrage nötig.

## Folgen

- Das reine Anzeigen oder Bearbeiten einer Notiz hat keine externe Wirkung.
- HTTP, FTP, `javascript:`, eingebettete Zugangsdaten und entfernte Datei-URLs
  werden nicht als öffnbare Aktionen angeboten.
- Ein nach der Anzeige ausgetauschtes lokales Ziel wird beim bestätigten
  Öffnungsversuch erneut geprüft.
- Die Anwendung erlaubt bewusst nicht jedes Betriebssystem-Schema. Weitere
  Zielarten brauchen eine eigene Richtlinie und Tests.
- Der Browser beziehungsweise die registrierte lokale Anwendung bleibt nach
  der Bestätigung die ausführende Sicherheitsgrenze; FinanzVerwalter rendert
  fremde Inhalte nicht selbst.
