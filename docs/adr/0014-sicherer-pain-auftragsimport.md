# ADR 0014: Sicherer pain-Auftragsimport erzeugt nur Entwürfe

- Status: angenommen
- Datum: 31.07.2026

## Kontext

Lokale `pain.001.001.09`- und `pain.008.001.08`-Dateien können fremde oder
veraltete Stammdaten enthalten. Eine stillschweigende Zuordnung oder direkte
Geldwirkung würde falsche Empfänger, Mandate oder Doppelaufträge riskieren.

## Entscheidung

Der Import akzeptiert ausschließlich die beiden exakten ISO-Namespaces,
weist DTD/ENTITY ab und prüft Mengen, Kontrollsummen, Identifikatoren,
SEPA-Kernelemente und Beträge vor jeder Vorschau. Konten, Bankverbindungen
und Mandate werden nur über exakte aktive Stammdaten zugeordnet und im Commit
erneut geprüft. Mehrdeutige Lastschriften sind nicht importierbar;
Überweisungen dürfen ausdrücklich als unverbundene Entwürfe übernommen
werden. Auswahl und zweite Bestätigung speichern ausschließlich Entwürfe und
eine unveränderliche Importhistorie in einer Transaktion. Es gibt weder
Bankversand noch Statusänderung oder Buchung. Vollständige Mehrpositionsblöcke
werden als Sammler rekonstruiert; Teilauswahlen bleiben Einzelaufträge.

## Folgen

Der Ablauf ist vorsichtig, idempotent und nachträglich nachvollziehbar. Eine
Stammdatenänderung zwischen Vorschau und Commit führt zum vollständigen
Abbruch. Banken mit zulässigen, aber abweichenden Profilvarianten benötigen
spätere explizite Parsererweiterungen statt stiller Toleranz.
