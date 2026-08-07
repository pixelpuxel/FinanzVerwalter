# ADR 0039: Bestätigter Abbruch von SEPA-Aufträgen und Sammlern

## Status

Angenommen am 07.08.2026. Ergänzt ADR 0038 um Lastschriften und Sammler.

## Kontext

Die gemeinsame Zahlungszustandsmaschine erlaubt einen Abbruch aus `draft` und
`awaiting_user`. In der Oberfläche war dieser sichere Übergang jedoch nur für
einzelne Überweisungen erreichbar. Lastschriften und Sammler konnten deshalb
zwar angelegt und initialisiert, aber nicht bewusst verworfen werden. Löschen
würde ihren Auditverlauf und bei Sammlern die Mitgliedschaft verschleiern.

## Entscheidung

Einzelne, nicht gebündelte Lastschriften erhalten in `draft` und
`awaiting_user` eine eigene bestätigungspflichtige Abbruchaktion. Ihr
eingefrorener Gläubiger-, Zahler-, Bank- und Mandatsschnappschuss bleibt
unverändert; nur Status, Version, Aktualisierungszeit und Audit wachsen.

Ein Sammler erhält dieselbe Aktion in beiden Zuständen. Das Repository bewegt
Sammler und alle geordneten Mitglieder innerhalb einer SQLite-Transaktion nach
`cancelled`. Ein zwischenzeitlich abweichender Mitgliedsstatus verwirft den
gesamten Vorgang. Abbruch erzeugt weder Einzel- noch Teilbuchungen und gibt die
Mitglieder nicht zur separaten Weiterverarbeitung frei.

Lastschriftentwürfe prüfen bereits beim Anlegen die pain.008-relevanten
Längengrenzen, beide optionalen BICs und die Slashregeln für End-to-End-ID,
Mandatsreferenz und Gläubiger-ID. Das spätere Export-Gate bleibt als zweite,
unabhängige Verteidigung bestehen.

## Folgen

Alle lokalen SEPA-Auftragsarten besitzen eine konsistente, sichtbare und
revisionssichere Abbruchsemantik. Terminal abgebrochene Aufträge und Sammler
können nicht erneut eingereicht werden. Lastschriftentwürfe bleiben wegen des
fachlich eingefrorenen Mandatsschnappschusses weiterhin nicht editierbar.
