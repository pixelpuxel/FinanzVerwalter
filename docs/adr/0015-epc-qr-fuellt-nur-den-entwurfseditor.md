# ADR 0015: EPC-QR füllt nur den überprüfbaren Entwurfseditor

- Status: angenommen
- Datum: 31.07.2026

## Kontext

Ein QR-Code auf einer Rechnung ist fremde Eingabe und kann von deren
Klartextangaben abweichen. Ein automatisches Speichern oder Ausführen würde
Manipulationen und versehentliche Zahlungen begünstigen.

## Entscheidung

FinanzVerwalter liest genau einen QR-Code aus einem lokalen Bild offline über
macOS Vision. Der Parser folgt EPC069-12 Version 3.1 und akzeptiert nur
BCD/001–002/SCT. Er prüft deklarierten Zeichensatz und 331-Byte-Grenze,
Feldzahl/-längen, BIC, IBAN, EUR-Betrag, Zweckcode, ISO-11649-RF-Prüfsumme
und die alternative Belegung von strukturierter Referenz und Freitext.
Bildgröße und -abmessung sind begrenzt; kein oder mehrere QR-Codes führen zum
Abbruch. Die Daten füllen ausschließlich den bereits vorhandenen sichtbaren
Überweisungseditor. Erst dessen normale Prüfung und bewusster Speichern-Befehl
erzeugen einen Entwurf. Es gibt keinen Versand und keine Buchung.

Migration 28 ergänzt Überweisungsaufträge um einen optionalen, validierten
SEPA-Zweckcode. Er gehört zur Idempotenzkennung, bleibt im unveränderlichen
Auftrag sichtbar und wird als `Purp/Cd` im pain.001-Export ausgegeben.

## Folgen

Der Nutzer kann QR- und Rechnungs-Klartext vor dem Speichern vergleichen.
Der Scanner funktioniert ohne Netzwerk und neue Abhängigkeit. Kamera-Livebild
und reine Point-of-Interaction-QR-Verfahren sind nicht Teil dieses
Rechnungsprofils.
