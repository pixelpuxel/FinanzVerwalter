# ADR 0031: Vollständiger Serienpayload aus einer Buchung

## Status

Angenommen am 07.08.2026.

## Kontext

Eine Kontoblattbuchung soll direkt als regelmäßiger Vorgang gespeichert werden
können. Die bisherige Serientabelle enthielt jedoch nur Hauptkategorie und
Gesamtbetrag. Ein bloßes Kopieren dieser Felder würde Splits, Tags,
Mehrwertsteuer und Fremdwährung verlieren und damit gerade komplexe reale
Buchungen fachlich verändern.

## Entscheidung

Schema 38 ergänzt `scheduled_transactions.transaction_template_json`. Der
optionale, sortiert codierte `TransactionTemplate`-Payload enthält alle
fachlichen Buchungsdetails. Die sichtbaren Serienfelder bleiben für Suche,
Bearbeitung und bestehende Dateien erhalten und werden vor dem Speichern mit
dem Payload synchronisiert. Der Store validiert Konto, Währung und die daraus
rekonstruierte Buchung.

Jede virtuelle Instanz erhält neue Buchungs- und Split-IDs, Status `Erwartet`
und nur die stabile Serienreferenz. Bank-, Import-, Provider-, Saldo- und
Abgleichsidentitäten werden entfernt. Ändert eine Ausnahme oder Revision
Betrag oder Kategorie, werden strukturelle Splits, MwSt. und Fremdwährung
entfernt; eine rechnerisch falsche Aufteilung wird niemals fortgeschrieben.

## Folgen

Alte Schema-37-Serien bleiben unverändert und besitzen zunächst keinen
Payload. Neue direkt übernommene Serien sind verlustfrei. Im Serieneditor sind
Betrag und Hauptkategorie geschützt, wenn eine Split-, Steuer- oder
Fremdwährungsinvariante davon abhängt. Eine einzelne Umbuchungsseite bleibt
unzulässig, weil ihre Gegenbuchung nicht als unabhängige Serie kopiert werden
darf.
