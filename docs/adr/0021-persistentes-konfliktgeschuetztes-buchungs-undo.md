# ADR 0021: Persistentes, konfliktgeschütztes Buchungs-Undo

## Status

Akzeptiert am 07.08.2026.

## Kontext

Die Regel-Engine besaß bereits ein spezialisiertes Undo. Manuelles Erstellen,
Bearbeiten, Verschieben, Organisieren und Löschen von Buchungen konnte dagegen
nicht als vollständiger fachlicher Vorgang zurückgenommen werden. Das ist bei
Splits, Tags, Steuerfeldern und zweiteiligen Umbuchungen mit einem einfachen
Feld-Diff nicht zuverlässig lösbar.

## Entscheidung

Schema 31 ergänzt `transaction_undo_runs`. Jede unterstützte lokale Mutation
schreibt in derselben SQLite-Transaktion einen vollständigen normalisierten
Vorher- und Nachher-Snapshot aller betroffenen `FinanceTransaction`-Objekte.
Eine monotone SQLite-Sequenz definiert die Reihenfolge auch bei mehreren
Änderungen innerhalb derselben Sekunde.

Vor einem Undo muss der aktuelle vollständige Zustand exakt dem gespeicherten
Nachher-Zustand entsprechen. Andernfalls wird ohne Teilwirkung abgebrochen.
Abgeglichene Buchungen bleiben zusätzlich geschützt. Bei Erfolg werden alle
Nachher-Seiten atomar entfernt, alle Vorher-Seiten einschließlich ursprünglicher
IDs und Splitstrukturen wiederhergestellt, das Paket einmalig entwertet und die
Aktion auditiert. Ein Umbuchungspaar ist immer eine gemeinsame Undo-Einheit.

## Folgen

- Erstellen, Bearbeiten, Verschieben, Massenorganisation, Löschen und
  Umbuchungserstellung lassen sich aus dem Kontoblatt sicher zurücknehmen.
- Zwischenzeitliche Änderungen können nicht still überschrieben werden.
- Die vollständigen Snapshots benötigen mehr Speicher als Feld-Diffs, sind
  dafür schema- und fachlich nachvollziehbar.
- Redo und Anhänge sind nicht Bestandteil dieser Entscheidung.
