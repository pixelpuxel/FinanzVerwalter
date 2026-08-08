# ADR 0005: Versionierter pain.001-Export vor Live-Banking

## Status

Angenommen am 31.07.2026.

## Kontext

Der Master-Prompt verlangt einen funktionsfähigen Simulator und Dateiwege,
bevor ein Live-Banking-Adapter aktiviert wird. ISO-20022-Nachrichten und die
SEPA-Implementierungsrichtlinien entwickeln sich unabhängig von der
Anwendungslogik weiter. Eine hart im UI verstreute Versionsnummer wäre nicht
prüfbar und später kaum sicher ablösbar.

Der seit 05.10.2025 geltende EPC-Regelstand für SCT C2PSP basiert auf der
2019er ISO-Nachricht `pain.001.001.09`. Die offiziellen Leitlinien fordern
unter anderem Kontrollsummen und bei Echtzeitüberweisungen den lokalen
Instrumentcode `INST`.

## Entscheidung

- `Pain001RulePackage` ist die einzige Quelle für Namespace, Kennung,
  Gültigkeitszeitraum und fachliche Quellenbezeichnung.
- Der erste Writer unterstützt genau `EPC-SCT-2025-V1.0` und verweigert
  Exportzeitpunkte vor dessen Gültigkeitsbeginn.
- Der Export ist lokal, deterministisch und zustandslos. Er sendet nichts,
  verändert keinen Auftrag und speichert keine Autorisierungsdaten.
- Der Initiierungsexport ist ausschließlich für unveränderte Entwürfe auf
  nicht geschlossenen Auftraggeberkonten erlaubt. Das verhindert einen
  Dateiexport als unbeabsichtigten Retry nach unbekanntem oder terminalem
  Status.
- Geld bleibt `Int64` in Minor-Units und wird ohne binäre Gleitkommazahl in
  zwei Dezimalstellen geschrieben.
- Auftraggeber- und Auftragsdaten werden vor dem Writer validiert. Fehlende
  Schuldner-BIC wird mit `NOTPROVIDED` abgebildet; eine fehlende optionale
  Empfänger-BIC erzeugt keinen leeren Bankblock.
- XCTest prüft Geschäftsinvarianten und XML-Inhalte; `xmllint` prüft eine
  erzeugte Referenzdatei zusätzlich gegen das generische V09-XSD.

## Folgen

Weitere Regelstände werden als neue, datierte Pakete ergänzt und über ein
explizites Auswahlverfahren aktiviert. `pain.001`-Import, Sammelaufträge,
Lastschriften (`pain.008`) und Statusberichte (`pain.002`) sind eigene
Arbeitspakete und werden durch diesen Export nicht vorgetäuscht.

## Quellen

- [EPC 2025 SCT Customer-to-PSP Implementation Guidelines](https://www.europeanpaymentscouncil.eu/document-library/implementation-guidelines/sepa-credit-transfer-customer-psp-implementation-1)
- [EPC 2025 SCT Rulebook und Implementierungsrichtlinien](https://www.europeanpaymentscouncil.eu/what-we-do/epc-payment-schemes/sepa-credit-transfer/sepa-credit-transfer-rulebook-and)
- [ISO-20022-Nachrichtenarchiv](https://www.iso20022.org/catalogue-messages/iso-20022-messages-archive?search=pain.001)
