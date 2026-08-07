# ADR 0029: Kreditraten als reversible Splitzuordnung

## Status

Angenommen am 07.08.2026. Erweitert ADR 0024 um echte Ist-Zahlungen.

## Kontext

Eine Bank liefert die Kreditrate gewöhnlich als einzelne Belastung. Für
Tilgungsplan, Kategorien und Auswertungen werden dagegen Tilgung, Sollzins,
Gebühr und Sondertilgung getrennt benötigt. Eine Zuordnung darf die reale
Bankbuchung nicht irreversibel verändern und darf nicht doppelt erfolgen.

## Entscheidung

Schema 37 speichert je Planfälligkeit genau eine `loan_payment_matches`-Zeile
mit Transaktions-ID, Komponenten, Herkunft und dem serialisierten Zustand vor
und nach dem Matching. Eine vorhandene, passende Kontobelastung wird atomar
aufgeteilt; alternativ wird eine neue Planraten-Splitbuchung erzeugt.
Datenbanktrigger schützen zugeordnete Transaktionen vor Änderungen und
Löschungen über gewöhnliche Buchungswege.

Beim Lösen wird eine erzeugte Buchung entfernt. Eine vorhandene Buchung wird
nur dann exakt aus dem Originalzustand rekonstruiert, wenn sie noch dem
gespeicherten Matching-Zustand entspricht. Plan/Ist-Bericht, CSV, PDF und Druck
lesen ausschließlich den gemeinsam erzeugten Snapshot.

## Folgen

Ist-Zahlungen und Abweichungen sind prüfbar, ohne Bankdaten zu verlieren oder
Planwerte als Realität auszugeben. Für bewusst zugeordnete Buchungen ist vor
einer normalen Bearbeitung zuerst die Zuordnung zu lösen. Kredit-Szenarien
bleiben eine getrennte spätere Funktion.
