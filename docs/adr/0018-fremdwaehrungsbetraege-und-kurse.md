# ADR 0018: Fremdwährungsbeträge und reproduzierbare Kurse

## Status

Angenommen am 07.08.2026.

## Kontext

Konten besaßen bereits einen ISO-Währungscode, Geldbeträge wurden jedoch
pauschal als zwei Dezimalstellen interpretiert. Eine Umbuchung schrieb auf
beiden Kontoseiten denselben Minor-Unit-Wert. Das ist zwischen EUR, USD oder
einer null- beziehungsweise dreistelligen Währung fachlich falsch und lässt
den tatsächlich bezahlten Originalbetrag nicht mehr rekonstruieren.

## Entscheidung

Der gebuchte Betrag bleibt ein `Int64` in der kleinsten Einheit der
Kontowährung. Die Anzahl der Nachkommastellen stammt aus `NumberFormatter`.
Alle Skalierungen und Umrechnungen erfolgen mit `Decimal` und `.bankers`.

Eine Fremdwährungsbuchung speichert als untrennbares Tripel den
Originalbetrag, dessen dreistellige ISO-Währung und den Kurs
„Kontowährung je Originalwährung“. Der Kurs ist ein positiver `Int64` mit dem
festen Faktor 100.000.000. Die Modellvalidierung rechnet das Tripel zurück und
erlaubt höchstens eine kleinste Kontowährungseinheit Rundungsabweichung.

Transfers gleicher Währung verlangen identische Beträge. Transfers
verschiedener Währungen speichern den tatsächlichen Abgang und Zugang je
Konto. Beide Seiten enthalten den jeweiligen Gegenbetrag als Originalbetrag
und den passenden Kurs; sie entstehen zusammen mit dem Audit-Ereignis in
einer SQLite-Transaktion. Schema 30 ergänzt die drei nullable beziehungsweise
leer vorbelegten Spalten an `transactions`.

## Folgen

- Saldo und laufender Saldo bleiben exakt in der jeweiligen Kontowährung.
- Eine Fremdwährungsbuchung und ihre Vorlage können Originalbetrag und Kurs
  verlustfrei erneut öffnen.
- Unterschiedliche Währungen werden in Übersichten weiterhin getrennt
  ausgewiesen und ohne explizite Bewertungsregel nicht addiert.
- Historische Marktpreisreihen, automatische Kursanbieter und
  Stichtagsumrechnung in Berichten bleiben eigenständige Folgearbeiten.
