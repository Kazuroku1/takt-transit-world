# Takt — Deine Stadt. Dein Netz.

Spielbare erste Beta eines ÖV-Aufbauspiels für iPhone, iPad und Browser. React + TypeScript, eine animierte Three.js-Miniaturstadt und ein natives iOS-Projekt mit Capacitor.

## Starten

Voraussetzung: Node.js 22 oder neuer.

```sh
npm ci
npm run dev
```

Im Browser: <http://localhost:5173>. Auf einem iPhone im selben WLAN die Netzwerk-Adresse öffnen, die Vite im Terminal anzeigt. Ein eventuell erscheinender Windows-Firewall-Dialog muss den lokalen Zugriff erlauben.

```sh
npm test
npm run build
npm run preview
```

## Spiel

- Start in Zürich mit einer fahrenden Buslinie und 1 200 Münzen.
- Ausschliesslich **vordefinierte Linien kaufen und freischalten**. Strecken und Haltestellen stehen fest.
- Bus, Tram, Zug, Metro, Schiff, Seilbahn und Flugzeug; neun Linien je Stadt, bis zu fünf Fahrzeuge pro Linie.
- Sichtbare Fahrzeuge und Fussgänger, drehbare und zoombare 3D-Stadt, Tag/Nacht, optionale Erfolgstöne.
- Fahrgelder, Kapazitätsausbau, XP und Level, Meilensteine und Tagesaufgaben, vorübergehende Einnahmenboni.
- Acht erschliessbare Städte: Zürich, Bern, Paris, London, New York, Tokio, Rio de Janeiro und Sydney. Jede Stadt hat einen eigenen persistenten Linienbestand. Alle erschlossenen Netze verdienen gleichzeitig, solange die App sichtbar läuft.
- Automatischer lokaler Spielstand, Export/Import in den Einstellungen, Pause und bis zu dreifaches Tempo.

Die Städte sind stilisierte Miniaturwelten. Sie verwenden in dieser Beta dieselbe Strassengrundstruktur mit variierten Gebäuden und lokalisierten Haltestellennamen, keine geografisch originalgetreuen ÖV-Netze. Im Hintergrund oder bei geschlossener App pausiert die Simulation. Kein Konto, Server, Abo oder In-App-Kauf erforderlich.

## Kostenlos aufs iPhone, mit Windows

Für den persönlichen Test ist kein bezahltes Entwicklerkonto nötig. Der vorbereitete Workflow `.github/workflows/ios-sideload.yml` baut auf einem GitHub-Mac eine unsignierte `Takt.ipa`. **AltStore Classic / AltServer für Windows** signiert und installiert sie anschliessend mit einem normalen Apple-Konto. Diese Fassung ist eine separat installierte Capacitor-Hybrid-App; es wird keine Safari-Verknüpfung verwendet.

1. Das Projekt in ein GitHub-Repository hochladen, inklusive `ios/`, `src/`, `scripts/`, `package-lock.json` und `.github/`; `node_modules/`, `dist/` und `build/` nicht hochladen.
2. Im Repository **Actions → iPhone-App bauen (AltStore) → Run workflow** öffnen. Der Workflow startet nur manuell und verwendet einen Standard-Runner, keinen kostenpflichtigen grösseren Runner.
3. Nach erfolgreichem Build das Artefakt **Takt-iPhone-AltStore** herunterladen und entpacken. Darin liegt `Takt.ipa`. Das Artefakt wird nach einem Tag gelöscht.
4. [AltStore Classic gemäss offizieller Windows-Anleitung installieren](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Das iPhone an den PC anschliessen, dem Computer vertrauen und bei Bedarf den Entwicklermodus aktivieren.
5. `Takt.ipa` auf das iPhone übertragen, in AltStore unter **My Apps → +** auswählen und installieren. Das Apple-Konto wird lokal in AltServer/AltStore eingerichtet; der Cloud-Build benötigt keine Apple-Zugangsdaten.
6. App mindestens alle sieben Tage mit AltServer erneuern. Das geht per USB oder, bei eingerichteter Synchronisierung, im selben WLAN. Kostenlose Konten erlauben höchstens drei gleichzeitig aktive sideloaded Apps; AltStore zählt mit.

**Kostenrahmen:** Standard-Runner sind für öffentliche GitHub-Repositories kostenlos. Private Repositories haben ein kostenloses Kontingent; vor dem Start muss genügend davon übrig sein und eine Kostenbegrenzung auf 0 gesetzt sein, wenn keine Kosten entstehen dürfen. Das Projekt wird nicht ohne Entscheidung des Eigentümers öffentlich gemacht. [GitHub-Abrechnung](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [AltStore-Limits](https://faq.altstore.io/altstore-classic/your-altstore).

Der erste [Cloud-Build mit Xcode 26](https://github.com/Kazuroku1/takt-transit-world/actions/runs/40695807396) hat das iPhone-Archiv und `Takt.ipa` erfolgreich erzeugt. Die lokal heruntergeladene Installationsdatei liegt in `build/Takt.ipa`. Die Installation auf einem physischen iPhone muss noch mit AltStore durchgeführt werden. Eine kurze Anleitung steht in `INSTALLATION.txt`.

## Optional: TestFlight mit Entwickler-Mitgliedschaft

Das Xcode-Projekt liegt unter `ios/App/App.xcodeproj`. App-ID: `ch.takt.transitworld`. App-Icon und Startbild sind enthalten. Das native Projekt verwendet Swift Package Manager; CocoaPods ist nicht nötig.

Der JavaScript-Build und das Kopieren ins iOS-Projekt funktionieren auch auf Windows. **Zum Kompilieren wird macOS mit Xcode 26 oder neuer benötigt; den Mac kann wie beim getesteten GitHub-Workflow ein Cloud-Anbieter bereitstellen.** Für TestFlight sind zusätzlich die kostenpflichtige Apple-Developer-Mitgliedschaft sowie Signierung und Upload nötig. Der kostenlose AltStore-Weg oben verwendet dagegen eine unsignierte IPA und signiert erst auf deinem Windows-PC für dein Gerät.

Auf dem Mac:

```sh
npm ci
npm run ios:sync
npm run ios:open
```

1. In Xcode das App-Target öffnen. Unter **Signing & Capabilities** das eigene Developer-Team wählen; bei Bedarf eine eigene, verfügbare Bundle-ID in Xcode und `capacitor.config.ts` setzen.
2. Auf einem iPhone oder im Simulator starten und Grafikleistung, Safe Areas, Speicherstand und Touch-Steuerung prüfen.
3. In App Store Connect eine App mit derselben Bundle-ID anlegen. Version ist `0.1.0`, Build `1`; für spätere Uploads die Build-Nummer erhöhen.
4. In Xcode ein generisches iOS-Gerät als Ziel wählen, **Product → Archive**, dann **Distribute App → App Store Connect → Upload**.
5. Nach der Verarbeitung den Build im **TestFlight**-Reiter auswählen, Testinformationen und Feedback-Kontakt eintragen und Tester einladen. Externe Tests können Apples Beta-Review erfordern.

Anleitungen: [Capacitor iOS](https://capacitorjs.com/docs/ios), [Capacitor-Systemvoraussetzungen](https://capacitorjs.com/docs/getting-started/environment-setup), [Apple: Builds hochladen](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), [Apple: TestFlight](https://developer.apple.com/testflight/).

Nach jeder Änderung am Spiel vor dem nächsten Xcode-Build `npm run ios:sync` ausführen. Die App enthält ihre Grafiken, Schriften und Spiel-Dateien lokal und benötigt zum Spielen keine Netzwerkverbindung.

## Projektstruktur

| Datei | Zweck |
| --- | --- |
| `src/game.ts` | Linien, Städte, Wirtschaft, Quests, Spielstandprüfung |
| `src/game.test.ts` | Tests für Käufe, Progression, Belohnungen und Spielstände |
| `src/CityScene.tsx` | 3D-Stadt, Verkehrsanimation und Kamera |
| `src/App.tsx` | Touch-Oberfläche, Menüs und lokale Speicherung |
| `src/styles.css` | Desktop-, iPad- und iPhone-Layout |
| `capacitor.config.ts` | Native App-Konfiguration |
| `scripts/native-assets.mjs` | App-Icon und Startbild aus dem vorhandenen SVG erzeugen |

Icons/Startbild neu erzeugen: `npm run assets:native`.

Die Capacitor-CLI ist bewusst auf `8.4.3` festgelegt: Die zum Entwicklungszeitpunkt neuere CLI zieht eine als verwundbar gemeldete `uuid`-Abhängigkeit nach. Core und iOS verwenden die im Lockfile festgehaltene Version `8.5.3`.
