# ADR 0025: Einzelne Serientermine behalten ihre Ursprungsidentität

## Status

Angenommen am 07.08.2026.

## Kontext

Eine einzelne Instanz eines regelmäßigen Vorgangs muss geändert,
übersprungen und wieder auf den Serienwert zurückgesetzt werden können. Wird
nur das wirksame Datum gespeichert, lässt sich eine verschobene Instanz beim
nächsten Erzeugen der Serie nicht mehr eindeutig zuordnen. Sie könnte erneut
erscheinen oder bei der Materialisierung doppelt gezählt werden.

## Entscheidung

Ab SQLite-Migration 33 speichert
`scheduled_transaction_exceptions` höchstens eine Ausnahme je Serien-ID und
ursprünglichem Fälligkeitsdatum. Dieses Datum bleibt unveränderliche
Identität. Eine Änderung überschreibt wirksames Datum, Empfänger,
Verwendungszweck, Kategorie und Betrag; eine Überspring-Ausnahme unterdrückt
die Instanz. Beide Dispositionen behalten die Herkunftskennung des
ursprünglichen Termins. Löschen der Ausnahme stellt ausschließlich diese
Instanz auf den Serienwert zurück. Speichern, Rücksetzen und Audit erfolgen
atomar.

## Folgen

Verschobene Termine bleiben über Neustarts stabil, werden von der
Materialisierungsprüfung erkannt und erscheinen nicht doppelt in der
Prognose. Übersprungene Termine bleiben in einer eigenen Ausnahmenliste
rücksetzbar. Änderungen an dieser und allen zukünftigen Instanzen werden als
separate Serienoperation umgesetzt und gehören nicht zu dieser Entscheidung.
