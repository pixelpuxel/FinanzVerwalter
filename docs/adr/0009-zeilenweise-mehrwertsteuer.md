# ADR 0009: Mehrwertsteuer wird je Buchungs- oder Splitzeile berechnet

Status: angenommen
Datum: 31.07.2026

## Kontext

FinanzVerwalter muss frei definierbare Mehrwertsteuerschlüssel einschließlich
mehrerer fachlich verschiedener 0-%-Schlüssel unterstützen. Eine Buchung kann
einen Schlüssel besitzen; bei Splitbuchungen kann jede Zeile einen anderen
Schlüssel verwenden. Brutto, Netto und Steuer müssen centgenau,
reproduzierbar und ohne binäre Gleitkommazahlen gespeichert werden.

## Entscheidung

- Migration 18 führt dateigebundene `vat_codes` mit stabiler UUID,
  Bezeichnung, Beschreibung, Satz in Basispunkten und Aktivstatus ein.
- 0 %, 7 % und 19 % werden als getrennte Standarddatensätze angelegt.
  Identität wird ausschließlich über die UUID bestimmt, niemals über den
  Prozentsatz.
- Kategorien erhalten Beschreibung, Budgetierbarkeit,
  Standard-MwSt.-Schlüssel, deutsche Steuerzuordnung und optionale
  US-Steuerzeile.
- Buchungen und Splitzeilen speichern Schlüssel, Modus, Netto und Steuer.
  Der Buchungsbetrag bleibt der Bruttobetrag.
- Automatische Berechnung behandelt den Betrag als brutto und rundet
  kaufmännisch auf Cent: `Steuer = Brutto × Satz / (100 % + Satz)`,
  `Netto = Brutto − Steuer`.
- Bei Splitbuchungen wird jede Zeile einzeln gerundet. Beleg-Netto und
  Beleg-Steuer sind danach ausschließlich die Summe der Zeilenwerte.
- Im manuellen Modus gibt der Nutzer den Steuerbetrag vor; Vorzeichen,
  Betragsschranke und die Invariante `Brutto = Netto + Steuer` werden geprüft.
- Buchungsvorlagen übernehmen die MwSt.-Felder, damit die Bedeutung bei einer
  späteren Anwendung erhalten bleibt.

## Folgen

Die Persistenz ist für steuerliche Zuordnungen und gemischte Splitbelege
geeignet, ersetzt aber keine Steuerberatung. Berichte verwenden bis zur
Erweiterung um explizite Netto-/Steuerspalten weiterhin den Bruttobetrag.
Bestehende Buchungen migrieren neutral mit Modus `none` sowie Netto und Steuer
gleich null.
