# ADR 0003: Banking als Adapter, Simulator vor Live-Zugang

- Status: angenommen
- Datum: 31.07.2026

## Kontext

Live-Banking ist bank-, zugangs-, bibliotheks- und aufsichtsabhängig. Ein
unklarer Zahlungsstatus darf niemals zu einer unbemerkten Wiederholung führen.

## Entscheidung

Zahlungsdomäne und SCA-Zustandsautomat werden zuerst vollständig lokal gegen
einen Simulator implementiert. TAN- oder Freigabecodes besitzen keine
Persistenzspalte. `unknown` ist terminal und kann nicht automatisch erneut
gesendet werden. Spätere FinTS-/PSD2-Implementierungen müssen hinter einem
versionierten Adaptervertrag liegen und normalisierte Ergebnisse atomar
übergeben.

## Folgen

Der lokale Zahlungsworkflow ist testbar, ohne einen echten Bankzugang
vorzutäuschen. Read-only-Abruf, FinTS-Kontakte und PSD2-Consent fehlen noch
und bleiben ausdrücklich offene P1-Anforderungen.
