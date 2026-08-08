# ADR 0010: Gestuftes, explizites Import-Matching

## Status

Akzeptiert am 31.07.2026.

## Kontext

Ein Dateibeleg oder späterer Bankabruf kann dieselbe wirtschaftliche
Buchung enthalten wie ein bereits manuell erfasster erwarteter Umsatz.
Reine Paket-Hashes verhindern nur den doppelten Import derselben Datei.
Ein unscharfer automatischer Merge kann dagegen Kategorien, Notizen,
Splits, Tags, Mehrwertsteuer oder bereits abgeglichene Daten beschädigen.

## Entscheidung

Migration 19 ergänzt Buchungen um Herkunft, Provider, externe
Transaktions-ID, Gegenkonto-IBAN, End-to-End-ID, Mandatsreferenz,
starken Fingerabdruck und optionalen Banksaldo nach der Buchung. Pro Konto,
Provider und nicht leerer externer Transaktions-ID erzwingt SQLite
Eindeutigkeit.

Der Import bewertet ausschließlich Umsätze desselben Kontos. Eine exakte
Provider-/Transaktions-ID ist ein harter Treffer und wird standardmäßig
übersprungen. Sonstige Kandidaten benötigen identischen Betrag und Währung
sowie ein einstellbares Datumsfenster. Referenz, End-to-End-ID,
Mandatsreferenz, IBAN, Empfänger und Verwendungszweck erhöhen einen
deterministischen Score.

Nur ein eindeutiger, finanziell kompatibler Kandidat ab 90 Punkten wird zum
Abgleich vorgeschlagen. Gleichstände und schwächere Treffer bleiben
explizite Entscheidungen. Die Vorschau bietet je Zeile `Neu importieren`,
`Überspringen` oder einen konkreten bestehenden Umsatz. Der Commit berechnet
alle Kandidaten gegen den aktuellen Datenbestand erneut und lehnt das
Erzwingen einer zweiten harten Bank-ID ab.

Beim Abgleich bleiben lokale Anreicherungen wie Kategorie, Memo, Splits,
Tags, Mehrwertsteuer und Transferstruktur erhalten. Bankidentität und
Bankmetadaten werden ergänzt; erwartete oder vorgemerkte Umsätze können zu
gebuchten Umsätzen werden. Abgeglichene Buchungen behalten ihre geschützten
fachlichen Felder.

## Folgen

- Kein stilles Zusammenführen unsicherer Kandidaten.
- Wiederholte Abrufe sind durch Datenbankinvariante und Commitprüfung
  idempotent.
- Paket-Idempotenz und buchungsbezogenes Matching bleiben getrennte
  Schutzschichten.
- Künftige OFX-, camt- oder Banking-Adapter müssen dieselben
  Identitätsfelder und denselben Commitpfad verwenden.
