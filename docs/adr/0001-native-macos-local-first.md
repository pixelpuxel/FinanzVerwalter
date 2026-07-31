# ADR 0001: Native macOS-Anwendung mit SwiftUI

- Status: angenommen
- Datum: 31.07.2026

## Kontext

Der aktuelle Workspace und seine verbindlichen Regeln priorisieren SwiftUI.
Die Anwendung muss auf dem vorhandenen Mac lokal installiert, bedienbar und
ohne Cloud-Anmeldung nutzbar sein. Die Masterdatei nennt Tauri und Windows 11
als Referenz, erlaubt aber eine andere Architektur, wenn der bestehende
Kontext sie vorgibt.

## Entscheidung

FinanzVerwalter wird zunächst als native macOS-Anwendung mit SwiftUI und
AppKit-Systemintegration entwickelt. Domänenmodelle und SQLite-Schema bleiben
UI-unabhängig benannt und werden nicht mit proprietären Plattformdiensten
vermischt.

## Folgen

- Native Tabellen, Menüs, Tastaturbedienung, Dynamic Type und Dark Mode sind
  ohne zusätzliche Laufzeit verfügbar.
- Der derzeitige Build benötigt keine Drittanbieterabhängigkeiten.
- Ein signierbarer Windows-Installer ist damit **nicht** erfüllt. Vor einer
  Windows-Auslieferung ist eine separate Oberfläche oder eine
  plattformübergreifende Neuausrichtung nötig. Dieser Punkt bleibt in der
  Anforderungsmatrix offen und darf nicht als abgeschlossen behauptet werden.
