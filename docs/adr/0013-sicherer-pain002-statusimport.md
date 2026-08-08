# ADR 0013: Zahlungsstatusberichte sind Historie mit expliziter Geldwirkung

## Status

Angenommen am 31.07.2026.

## Kontext

Ein ISO-20022-Statusbericht kann finale und vorläufige Zustände sowie
Gruppen-, Zahlungsblock- und Transaktionsreferenzen mischen. Eine ungenaue
Zuordnung oder die Gleichsetzung eines Zwischenstands mit einer Annahme würde
lokale Buchungen zu früh oder doppelt erzeugen. Sammelaufträge dürfen außerdem
nicht positionenweise in einen inkonsistenten Teilzustand geraten.

## Entscheidung

FinanzVerwalter importiert ausschließlich `pain.002.001.10` im exakten
Namespace. DTDs und externe Entitäten sind verboten; Größe, Positionszahl und
Pflichtstruktur sind begrenzt. Der SHA-256-Fingerabdruck des Quelldokuments ist
dateiweit eindeutig.

Die Zuordnung verwendet nur exakte, von den eigenen pain-Exporten erzeugte
Nachrichten-, Zahlungsblock- und End-to-End-IDs. `ACSC` ist die einzige finale
Annahme und `RJCT` die einzige finale Ablehnung. Alle übrigen Codes werden
unverändert historisiert, verändern jedoch weder lokalen Status noch Geld.
Transaktionszeilen eines Sammelauftrags bleiben informativ; nur der exakt
referenzierte Sammler darf samt Mitgliedern atomar wechseln.

Unmittelbar vor dem Commit wird die Vorschau gegen den aktuellen Datenbestand
neu berechnet. Bericht, Positionen, Statusänderungen und eventuell entstehende
genau-einmalige Buchungen werden in einer äußeren SQLite-Transaktion mit
Savepoints gespeichert. Jeder Fehler rollt die gesamte Wirkung zurück.

## Folgen

Ein Statusbericht ist vollständig auditierbar und wiederholtes Einlesen bleibt
wirkungslos. Vorläufige Bankantworten sind sichtbar, ohne einen Zahlungserfolg
vorzutäuschen. Finale Sammelantworten können keinen Teilstatus erzeugen. Die
enge Versions- und Referenzbindung bedeutet bewusst, dass andere
`pain.002`-Versionen oder bankeigene Referenzvarianten zunächst abgewiesen
werden und erst mit eigenen Tests als versioniertes Regelpaket hinzukommen.

## Quellen

- [ISO-20022-Nachrichtenarchiv](https://www.iso20022.org/catalogue-messages/iso-20022-messages-archive?search=pain.002)
- [EPC 2025 SDD Customer-to-PSP Implementation Guidelines](https://www.europeanpaymentscouncil.eu/document-library/implementation-guidelines/sepa-direct-debit-core-customer-psp-implementation-0)
