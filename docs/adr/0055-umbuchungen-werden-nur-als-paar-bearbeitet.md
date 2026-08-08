# ADR 0055: Umbuchungen werden nur als Paar bearbeitet

## Status

Akzeptiert am 08.08.2026.

## Entscheidung

Eine im Kontoblatt gewählte Transferseite wird nicht im allgemeinen
Buchungseditor bearbeitet. Der eigene Umbuchungseditor lädt beide Seiten und
ändert Datum, Zweck und Beträge atomar. Quell- und Zielkonto bleiben fest;
Fremdwährungsbeträge, Originalwerte und reziproke Kurse werden gemeinsam neu
berechnet. Der allgemeine Einzelpfad weist vorhandene und neu übergebene
Transferidentitäten ab.

## Folgen

- Kein UI- oder Repositorypfad kann nur eine Seite eines Transfers verändern.
- Beide Transaktions-IDs und die gemeinsame Transfer-ID bleiben stabil.
- Abgleichschutz, Audit und konfliktgeschütztes Undo gelten für das gesamte
  Paar.
- Ein Kontowechsel erfordert weiterhin Löschen und bewusstes Neuanlegen des
  Transfers, damit keine verdeckte Saldenverschiebung entsteht.
