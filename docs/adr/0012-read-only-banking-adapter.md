# ADR 0012: Read-only-Banking-Adapter mit atomarer Übernahme

## Status

Akzeptiert am 31.07.2026.

## Kontext

Bankprotokolle, Zustimmungslebenszyklen und anbieterspezifische Antworten
dürfen weder die Finanzdomäne bestimmen noch unvollständige Daten direkt in
Kontenblätter schreiben. Eine produktive FinTS- oder PSD2-Anbindung benötigt
zusätzliche Provider-, Lizenz-, SCA-, Datenschutz- und Sicherheitsarbeit.
Trotzdem müssen Zuordnung, Vorschau, Matching, Regeln und Commit bereits mit
realistischen Paketen reproduzierbar prüfbar sein.

## Entscheidung

Der `ReadOnlyBankingAdapter` liefert ausschließlich normalisierte
Konten, Salden, Umsätze, Auftragsbestände und pro Vorgang eine Diagnose.
Adapter schreiben nicht in SQLite. Rohe Antworten werden verworfen; für
Nachvollziehbarkeit bleibt nur ein SHA-256-Hash.

Der lokale Simulator implementiert den Vertrag deterministisch und ohne
Zugangsdaten. Sein Funktionsumfang ist ehrlich auf Konten, Salden, gebuchte
und vorgemerkte Umsätze, Daueraufträge und Terminüberweisungen begrenzt.
Depotbestand und Kurse werden nicht als unterstützt ausgegeben. Andere
Providerarten können nicht persistiert oder aktiviert werden.

Eine separate Normalisierung ordnet jedes externe Konto genau einem lokalen
Konto gleicher Währung zu, erzeugt stabile externe Transaktionsidentitäten,
wendet konfliktfreie Regeln in Prioritätsreihenfolge an und verwendet danach
das gestufte Import-Matching. Regelwirkungen und Konflikte bleiben in der
Vorschau sichtbar.

Der Commit validiert Adapter, Diagnose, Zuordnung, Währung und
Importentscheidungen erneut. Buchungen, Banksalden, Auftragsbestand,
Abrufhistorie und Verbindungstatus werden gemeinsam in genau einer
SQLite-Transaktion geschrieben. Wiederholte Pakete können nur als
vollständige Skip-Läufe protokolliert werden. Abbruch und Fehler erzeugen
keine partiellen Fachdaten.

## Folgen

- Protokolladapter bleiben austauschbar und von der Finanzdomäne getrennt.
- Live-Banking wird nicht vorgetäuscht; deaktivierte Provider sind sichtbar.
- Derselbe sichere Matchingpfad gilt für Datei- und Bankimporte.
- Der Simulator ermöglicht End-to-End-Tests ohne reale Bank- oder Kundendaten.
- Vor einem Live-Adapter sind SCA-Interaktionen, Consent-Lebenszyklus,
  Geheimnisspeicher, Logging-Redaktion und Providerzulassung separat zu
  entscheiden und zu testen.
