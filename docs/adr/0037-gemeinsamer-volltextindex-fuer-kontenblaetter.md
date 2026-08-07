# ADR 0037: Gemeinsamer Volltextindex für Kontenblätter

## Status

Angenommen am 07.08.2026.

## Kontext

Ein Kontenblatt muss Buchungen nicht nur über Empfänger und Zweck finden.
Kontofelder, vollständige Hierarchien, Beträge, Salden und technische
Bankreferenzen sind ebenso relevante Suchmerkmale. Ein linearer Vergleich
jeder Zeile bei jedem Tastendruck liefert bei großen Finanzdateien kein
verlässlich unmittelbares Feedback. Eine reine Präfixsuche würde bestehende
Wortteiltreffer wie `steuer` in `Grundsteuer` verlieren.

## Entscheidung

`RegisterSearchIndex` erzeugt beim Laden ein normalisiertes Dokument je
persistenter Buchung und einen invertierten Index aus ein-, zwei- und
dreistelligen Zeichenfragmenten. Groß-/Kleinschreibung, Diakritika und
Interpunktion werden vereinheitlicht. Mehrere Suchtokens werden als logisches
UND ausgewertet, dürfen aber in beliebigen unterschiedlichen Feldern stehen.

Die Fragmentmengen reduzieren zunächst die UUID-Kandidaten. Danach prüft das
vollständige normalisierte Dokument jeden Wortteil, sodass keine falschen
Trigramm-Treffer ausgegeben werden. Einzel-, Zweit- und Sammelkontenblätter
verwenden dieselbe Abfrage. Nicht persistente Prognosezeilen werden mit
demselben Dokumentformat direkt geprüft.

## Folgen

Die Suche umfasst alle relevanten Buchungs-, Konto-, Hierarchie-, Geld-,
Saldo- und Bankreferenzfelder und behält innere Wortteiltreffer. Der Index
benötigt zusätzlichen Arbeitsspeicher und wird nach einem Repository-Reload
neu aufgebaut. Die interaktive Abfrage ist unabhängig vom Aufbau messbar;
ein Regressionstest fordert weniger als 100 ms bei 100.000 vorindexierten
Dokumenten.
