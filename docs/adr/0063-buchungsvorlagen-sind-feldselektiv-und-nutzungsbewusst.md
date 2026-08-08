# ADR 0063: Buchungsvorlagen sind feldselektiv und nutzungsbewusst

## Status

Angenommen am 08.08.2026.

## Kontext

Die bisherigen Buchungsvorlagen kopierten stets den vollständigen fachlichen
Inhalt. Damit konnten wiederkehrende Buchungen reproduziert werden, aber keine
Teilvorlagen, die beispielsweise nur Empfänger, Zweck und Kategorie vorgeben.
Außerdem fehlten eine reversible Deaktivierung und eine nachvollziehbare
Priorisierung häufig verwendeter Vorlagen.

## Entscheidung

Eine `TransactionTemplate` trägt optional einen Satz aus zwölf fachlichen
Feldern. Ein fehlender Satz steht aus Kompatibilitätsgründen für alle Felder.
Ein leerer Satz ist ungültig. Split-, MwSt.- und Fremdwährungsfelder hängen vom
Betrag ab und dürfen nicht ohne ihn gespeichert werden.

Migration 41 ergänzt die Tabelle `transaction_templates` um Aktivstatus,
Nutzungszahl und Zeitpunkt der letzten Verwendung. Fehlende Legacy-Werte
bedeuten aktiv, null Verwendungen und nie verwendet. Die Bibliothek bietet nur
aktive Vorlagen an und sortiert stabil nach Übereinstimmung mit dem aktuellen
Konto, Nutzungszahl, letzter Verwendung, Name und UUID.

Eine Verwendung wird erst nach einer erfolgreich gespeicherten Buchung in
derselben Datenbank protokolliert. Öffnen und Abbrechen verändern den Zähler
nicht. Deaktivieren bleibt reversibel; Löschen bleibt eine getrennte,
ausdrückliche Aktion.

## Folgen

- Teilvorlagen überschreiben keine abgewählten Felder.
- Vorlagen ohne Betrag beginnen mit einer leeren, zwingend auszufüllenden
  Betragseingabe.
- Häufige und kontospezifische Vorlagen sind schneller erreichbar, ohne eine
  nicht nachvollziehbare SmartFill-Schreibaktion auszulösen.
- Schema-40-Vorlagen bleiben vollständig und aktiv nutzbar.
- Nutzungsmetadaten bleiben finanzdateigebunden, gesichert und auditiert.
