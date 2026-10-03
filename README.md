# Spacer z historią

Przewodnik na HarmonyOS/OpenHarmony (API 20+), który idzie razem z tobą: wie, co jest przed tobą, płynnie łączy kolejne zabytki w jedną opowieść i mówi po polsku. **Bez stałego uprawnienia do lokalizacji**: lokalizację dostaje tylko po kliknięciu `LocationButton` i traci ją, gdy schodzi z ekranu. Tekst pisze lokalnie Bielik (Ollama), czyta ElevenLabs (zapasowo Piper offline). Projekt na HackYeah 2026, wyzwanie Huawei / OpenHarmony.

> 🚧 W trakcie hackathonu. Instrukcje build/run uzupełnia issue „README: setup, build, run”.

- Architektura: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Kontrakty danych i API: [`docs/CONTRACTS.md`](docs/CONTRACTS.md)
- Testy: [`docs/TESTING.md`](docs/TESTING.md)
- Organizacja pracy: [`docs/TEAM.md`](docs/TEAM.md), role: [`docs/ROLES.md`](docs/ROLES.md), backlog: [`tools/issues.md`](tools/issues.md)
- Użycie AI: [`AI_WORKFLOW.md`](AI_WORKFLOW.md)

## Dane
Opisy miejsc pochodzą z polskiej Wikipedii (MediaWiki GeoSearch API), licencja CC BY-SA 4.0. Dane demo dla trasy Barbakan → Wawel: `fixtures/`, generowane przez `tools/gen_fixtures.py`.

## Uruchomienie (stan na teraz)

**Serwer** (`server/`, Node ≥ 22.9, bez zależności), szczegóły w [`server/README.md`](server/README.md):

```sh
cd server
npm start     # port 8787; w logu adresy LAN, pod którymi emulator widzi laptopa
npm test      # testy bez sieci
```

Sprawdzenie w przeglądarce: `http://localhost:8787/v1/health` i `http://localhost:8787/v1/pois?lat=50.0617&lon=19.9373&radius=150`.

**Aplikacja** (`Projekt/`, DevEco Studio 6.x):

```sh
cd Projekt
devecocli build                     # buduje .hap
```

Testy jednostkowe (Hypium, lokalnie, bez emulatora) na macOS:

```sh
cd Projekt
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install        # tylko w świeżym klonie
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p module=entry@default -p product=default -p buildMode=test test --no-daemon
```

Połączenie aplikacji z serwerem: wpisz adres LAN laptopa do `API_BASE_URL` w `Projekt/entry/src/main/ets/data/ApiConfig.ets`. Pusty adres oznacza tryb offline: dane z `rawfile`, lokalne szablony.
