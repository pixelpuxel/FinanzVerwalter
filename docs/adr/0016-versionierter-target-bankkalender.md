# ADR 0016: Versionierter TARGET-Bankkalender

## Status

Angenommen am 31.07.2026.

## Kontext

Daueraufträge konnten Fälligkeiten bisher nur anhand von Samstag und Sonntag
verschieben. Das war reproduzierbar, bildete aber Euro-Bankarbeitstage nicht
ausreichend ab. Gleichzeitig sind SEPA-Echtzeitüberweisungen von klassischen
TARGET-Schließtagen zu unterscheiden.

Die Deutsche Bundesbank definiert TARGET-Geschäftstage als Montag bis Freitag
mit den zusätzlichen Schließtagen 1. Januar, Karfreitag, Ostermontag, 1. Mai,
25. und 26. Dezember. Dasselbe Kalenderprofil nennt die EZB für T2. Die
Bundesbank stellt zudem klar, dass SEPA-Echtzeitüberweisungen an allen Tagen
rund um die Uhr abgewickelt werden können.

Primärquellen:

- [Deutsche Bundesbank: Merkblatt unbarer Zahlungsverkehr an Feiertagen](https://www.bundesbank.de/resource/blob/671010/004a37865a3c96af7ddc08e057c3833d/mL/zv-merkblatt-feiertage-data.pdf)
- [EZB: T2 opening hours](https://www.ecb.europa.eu/paym/target/t2/html/index.en.html)

## Entscheidung

Migration 29 ergänzt Daueraufträge um `banking_calendar_id` und deren
Historienzeilen um Kalenderkennung und -version. `target-euro-v1` berechnet
die sechs offiziellen TARGET-Schließtage einschließlich gregorianischem
Karfreitag und Ostermontag. `weekdays-v1` erhält das frühere Verhalten als
bewusst auswählbares Kompatibilitätsprofil.

Die Verschiebungsregel bleibt getrennt: unverändert, nächster oder vorheriger
Bankarbeitstag. Jede materialisierte oder übersprungene Fälligkeit friert die
verwendete Kalenderkennung und Version ein. Überweisungs- und
Lastschrifteditor zeigen Schließtage als Warnung; Entwürfe bleiben editierbar.
Echtzeitüberweisungen werden als 24/7-Ausnahme gekennzeichnet.

## Folgen

- Historische Ausführungen bleiben auch nach einer künftigen Regeländerung
  erklärbar.
- Neue Regeln benötigen eine neue Profilkennung statt stiller Mutation von
  `target-euro-v1`.
- Regionale deutsche Feiertage und institutsspezifische Annahmeschlusszeiten
  werden nicht als TARGET-Schließtage behauptet.
- Eine Warnung ist keine Bankannahme und löst keine Übermittlung aus.
