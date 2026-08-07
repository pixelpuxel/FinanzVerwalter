# ADR 0041: Vollständige Kontostammdaten mit geprüftem Gegenkonto

## Status

Angenommen am 08.08.2026.

## Kontext

Kontotyp, Eröffnungsdatum und Eröffnungssaldo waren vorhanden. Für die
Kontenparität des Masterdokuments fehlten jedoch Untertyp, deutsche BLZ, ein
eigener Saldo-Stichtag, Schließdatum und die fachliche Zuordnung eines
Verrechnungs-, Anlage-, Darlehens- oder sonstigen Gegenkontos.

## Entscheidung

Schema 39 ergänzt `accounts` additiv um `subtype`, `bank_code`,
`opening_balance_date`, `closing_date` und `linked_account_id`. Die
Gegenkontoreferenz ist ein nullable Self-Foreign-Key mit `ON DELETE SET NULL`
und eigenem Index. Die Migration erhält alle Bestandsfelder; neue Werte sind
leer beziehungsweise `NULL`.

Jede SQLite-Verbindung wartet bis zu fünf Sekunden auf eine nur
vorübergehend belegte Datei. Das verhindert, dass ein unmittelbar nach dem
Beenden der Vorgängerversion gestarteter Migrationslauf wegen des kurzen
Freigabefensters abbricht; echte länger anhaltende Konkurrenz bleibt ein
sichtbarer Fehler.

Die Persistenz normalisiert Leerzeichen aus der BLZ und akzeptiert nur leer
oder genau acht Ziffern. Der Untertyp ist auf 80 UTF-8-Bytes begrenzt und darf
keine Steuerzeichen enthalten. Ein Schließdatum ist nur bei geschlossenem
Konto erlaubt. Saldo-Stichtag und Schließdatum dürfen die Kontoeröffnung nicht
zeitlich unterschreiten. Das Gegenkonto muss existieren und darf nicht das
Konto selbst sein.

Der Kontoeditor zeigt sämtliche Felder. Der direkte Schließen-Ablauf setzt den
lokalen heutigen Kalendertag, Wiederöffnen löscht ihn. Untertyp, BLZ und beide
zusätzlichen Datumsfelder fließen in die globale Kontenblattsuche ein.

## Folgen

Die Kontostammdaten lassen sich ohne Überladen des Kontotyps fachlich
differenzieren. Die generische Gegenkontobeziehung bildet mehrere vom Master
genannte Zuordnungsarten ab; eine spätere typisierte Mehrfachbeziehung würde
eine weitere Migration benötigen.
