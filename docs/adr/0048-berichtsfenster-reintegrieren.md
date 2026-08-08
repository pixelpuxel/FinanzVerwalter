# ADR 0048: Berichtsfenster verlustfrei reintegrieren

## Status

Angenommen am 08.08.2026.

## Kontext

Ein externer Bericht ist nur dann ein gleichwertiger Desktop-Arbeitsbereich,
wenn er nicht zur Sackgasse wird. Nutzer müssen eine dort weiterentwickelte
Abfrage wieder in die Hauptnavigation übernehmen können. Außerdem sollen
mehrere Berichtsfenster nach Verschieben und Skalieren ihre jeweilige
Geometrie behalten.

## Entscheidung

Das externe Fenster erzeugt aus seiner aktuellen Query und seinem sichtbaren
Titel einen `TransactionReportLaunchRequest` mit frischer UUID. Es sendet ihn
über denselben internen Navigationskanal, den direkte Berichtsaufrufe aus dem
Kontenblatt verwenden. `RootView` setzt Query, Titel und Launch-ID, wechselt
zur Berichtswerkstatt und initialisiert diese anhand der neuen Identität neu.
Danach schließt SwiftUI das typisierte Außenfenster; ein zentral registriertes,
schwach referenziertes `NSWindow` wird aktiviert und nach vorn geholt.

Ein unsichtbarer AppKit-Host registriert das Hauptfenster. Ein zweiter Host
weist jedem externen Fenster einen stabilen Frame-Autosave-Namen aus seiner
Request-UUID zu. Fremddatei- und Dekodierungsfehler bleiben vor der Übergabe
gesperrt.

## Folgen

- Query und Titel bleiben beim Wechsel zurück ins Hauptfenster erhalten.
- Auch dieselbe Query kann bewusst einen neuen Hauptansichtszustand auslösen.
- Außenfenster schließen kontrolliert nach erfolgreicher Übernahme.
- Position und Größe werden je Fensteridentität durch AppKit gesichert.
- Direkte Berichtsaufrufe aus Kontenblättern bleiben rückwärtskompatibel.
