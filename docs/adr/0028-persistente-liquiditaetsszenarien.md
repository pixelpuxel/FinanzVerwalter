# ADR 0028: Persistente Liquiditätsszenarien mit Herkunft

## Status

Akzeptiert am 07.08.2026.

## Kontext

Eine belastbare Liquiditätsplanung muss reale Salden, vorgemerkte und
erwartete Buchungen, Zahlungsaufträge, Daueraufträge, allgemeine
Serientermine und manuelle Annahmen erklären können. Ohne Herkunft und
Deduplizierungsregel würde ein bereits vorgemerkter Zahlungsauftrag leicht
mehrfach gezählt. Konten verschiedener Währungen dürfen nicht ohne Kursbasis
zu einer scheinbar exakten Summe verschmelzen.

## Entscheidung

Benannte Szenarien und Positionen werden ab Schema 35 in der Finanzdatei
versioniert, fremdschlüsselgesichert und auditiert gespeichert. Ein
Szenario-Aktivschalter entscheidet, ob seine aktivierten Positionen in die
Berechnung eingehen.

Eine reine Engine bildet tägliche, am Montag beginnende ISO-Wochen- und
Kalendermonatsintervalle. Sie liefert Anfang, Änderung, Schluss, Minimum,
Maximum und alle ursächlichen Positionen. Eine Berechnung umfasst stets nur
Konten derselben ISO-Währung.

Für planmäßige Quellen gilt der starke Deduplizierungsschlüssel Konto,
lokaler Tag, Minor-Unit-Betrag und normalisierte Bezeichnung. Die Priorität
ist reale Buchung, Zahlungsauftrag, Dauerauftrag, allgemeiner Serientermin.
Szenariopositionen sind additive Annahmen und werden nicht zusammengeführt.

## Folgen

Unterdeckungen und Szenarioeffekte sind bis zur Einzelposition erklärbar.
Materialisierte oder parallel vorgemerkte Zahlungen werden bei stark
identischem Inhalt nur einmal gezählt. Unsichere namens- oder
betragsähnliche Positionen werden nicht heuristisch verschmolzen. Für eine
übergreifende Mehrwährungsprognose wäre künftig eine ausdrücklich
versionierte Kursquelle erforderlich.
