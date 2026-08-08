# ADR 0020: Deterministisches XLSX ohne zusätzliche Abhängigkeit

## Status

Angenommen am 07.08.2026.

## Kontext

Die Berichtswerkstatt benötigt echte XLSX-Dateien. Eine neue Bibliothek wäre
für einen einzelnen, klar begrenzten Open-XML-Ausgabepfad unverhältnismäßig
und würde Release, SBOM und Angriffsfläche erweitern. Als CSV formatierte
Dateien mit falscher `.xlsx`-Endung sind nicht akzeptabel.

## Entscheidung

FinanzVerwalter schreibt ein minimales vollständiges SpreadsheetML-Paket mit
Workbook, Worksheet, Styles, Beziehungen, Content Types und Dokumentmetadaten.
Ein kleiner deterministischer ZIP-Writer erzeugt unkomprimierte Einträge mit
CRC-32 und stabilem Zentralverzeichnis. Geld bleibt als numerische
Dezimalzelle mit währungsabhängigem Format erhalten. Importierte Texte werden
als maskierte Inline-Strings ausgegeben, ungültige XML-Steuerzeichen entfernt
und niemals als Formel interpretiert.

Die Zwischenablage erhält parallel eine TSV- und eine HTML-Repräsentation aus
demselben unveränderlichen Berichtssnapshot.

## Folgen

- XLSX ist ohne Netzwerk und ohne neue Laufzeitabhängigkeit verfügbar.
- Identische Eingaben erzeugen byteidentische Pakete.
- ZIP-Integrität, XML, Golden-Hash, Formelinjektionsschutz und numerische
  LibreOffice-Konvertierung sind testbar.
- Der bewusst minimale Export enthält ein Arbeitsblatt und keine Diagramme.
