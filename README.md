# Spacer z historią

Przewodnik na HarmonyOS/OpenHarmony (API 20+), który idzie razem z tobą: wie, co jest przed tobą, płynnie łączy kolejne zabytki w jedną opowieść i mówi po polsku. **Bez stałego uprawnienia do lokalizacji**: lokalizację dostaje tylko na czas spaceru. Tekst pisze Bielik (polski otwarty model, nasze wdrożenie Ollamy na Modalu), czyta ElevenLabs (zapasowo Piper offline). Projekt na HackYeah 2026, wyzwanie Huawei / OpenHarmony.

- Architektura: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Kontrakty danych i API: [`docs/CONTRACTS.md`](docs/CONTRACTS.md)
- Testy: [`docs/TESTING.md`](docs/TESTING.md)
- Organizacja pracy: [`docs/TEAM.md`](docs/TEAM.md), role: [`docs/ROLES.md`](docs/ROLES.md), backlog: [`tools/issues.md`](tools/issues.md)
- Użycie AI i ewaluacja modelu: [`AI_WORKFLOW.md`](AI_WORKFLOW.md)

## Co działa, a co jest symulowane

| Element | Stan |
|---|---|
| Serwer: POI z Wikipedii, segmenty z Bielika, głos, łącze telefon ↔ zegarek | działa (`server/`) |
| Aplikacja: start, prywatność, ustawienia, silnik przewodnika | działa |
| Ekran spaceru (`WalkPage`) | **przykładowe dane** do czasu podpięcia `WalkViewModel` (#49) |
| Lokalizacja z GPS | **jeszcze nie ma** (#10, #48); `location/` i `session/` to zaślepki |
| Strona debug przewodnika (`GuideDebugPage`) | **symulacja**: odtwarza trasę demo ×N bez GPS i bez głosu, z etykietą „SYMULACJA” na ekranie |
| Łącze telefon ↔ zegarek na emulatorach | **symulacja przez serwer** (Super Device nie widzi emulatorów), na urządzeniach #57 |

Każdy segment w aplikacji ma etykietę pochodzenia: „AI · model · głos” albo szablon.

## Wymagania

| Do czego | Wersja |
|---|---|
| Aplikacja | DevEco Studio 6.1.x (Windows 10/11 x64 albo macOS na Apple Silicon), SDK HarmonyOS w zestawie: zgodność `6.0.0(20)`, target `6.1.1(24)` |
| Serwer | Node.js ≥ 22.9, bez zależności npm |
| Bielik (opcjonalnie) | konto [Modal](https://modal.com) + Python 3 (`pip install modal`) albo lokalna [Ollama](https://ollama.com) |
| Głos (opcjonalnie) | klucz ElevenLabs; zapasowo [Piper](https://github.com/rhasspy/piper) z głosem `pl_PL-gosia-medium` + ffmpeg |

**Ścieżka do repozytorium bez spacji i polskich znaków.** DevEco Studio (hvigor) odrzuca projekt w ścieżce typu `C:\Repozytoria\HackYeah 2026\…` („niedozwolone znaki”). Klonuj np. do `C:\dev\hack-yeah-2026`. Jeśli repozytorium już leży w złej ścieżce, wystarczy druga kopia robocza: `git worktree add C:\dev\hy26 <gałąź>`.

## Aplikacja (`Projekt/`)

### Emulator

1. Pierwsze uruchomienie DevEco Studio i instalacja SDK według [instrukcji Oniro](https://docs.oniroproject.org/application-development/environment-setup-guide/deveco-studio/installation/).
2. **Region CN** (bez tego emulator ma tylko zegarek): przy zamkniętym DevEco Studio w `%AppData%\Huawei\DevEcoStudio6.1\options\country.region.xml` (macOS: `~/Library/Application Support/Huawei/DevEcoStudio6.1/options/`) ustaw `<countryregion name="CN"/>`. Szczegóły: [quickstart wyzwania](https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/quickstart-guide.md).
3. *Tools → Device Manager → Local Emulator → New Emulator*: **Phone**, obraz systemu **API 20 lub nowszy**, pobierz i uruchom. Na Windows emulator wymaga włączonej „Platformy funkcji hypervisora systemu Windows”.

### Build, podpis, instalacja

1. *File → Open* → `Projekt/`, poczekaj na synchronizację (`ohpm install`).
2. Podpis: *File → Project Structure → Signing Configs → Automatically generate signature* (konto Huawei ID). DevEco dopisze lokalne ścieżki do `build-profile.json5`. **Nie commituj tej zmiany** ani plików `.p12`, `.cer`, `.p7b`.
3. Uruchomienie z IDE: wybierz emulator i *Run 'entry'*. Z wiersza poleceń:

```sh
cd Projekt
devecocli build                                                     # albo: hvigorw assembleHap --mode module -p product=default
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.example.myapplication
```

### Testy jednostkowe (Hypium, bez emulatora)

macOS:

```sh
cd Projekt
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install        # tylko w świeżym klonie
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p module=entry@default -p product=default -p buildMode=test test --no-daemon
```

Windows (PowerShell):

```powershell
cd Projekt
$d = 'C:\Program Files\Huawei\DevEco Studio'
$env:DEVECO_SDK_HOME = "$d\sdk"; $env:Path = "$d\tools\node;$env:Path"
& "$d\tools\ohpm\bin\ohpm.bat" install
& "$d\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@default -p product=default -p buildMode=test test --no-daemon
```

Wynik: `entry/.test/default/intermediates/test/coverage_data/test_result.txt` (linia `Tests run: …`), raport HTML w `entry/.test/default/outputs/test/reports/`.

### Połączenie z serwerem

Adres serwera to `API_BASE_URL` w `Projekt/entry/src/main/ets/data/ApiConfig.ets`. Pusty adres oznacza tryb offline (niżej).

- **Najprościej (niezależnie od sieci na hali):** przekieruj port emulatora na laptopa i wpisz `http://127.0.0.1:8787`:
  ```sh
  hdc rport tcp:8787 tcp:8787      # dla każdego uruchomionego emulatora (hdc -t <id> …, lista: hdc list targets)
  ```
- **Przez sieć:** adres LAN laptopa z logu `npm start` (np. `http://192.168.1.20:8787`). `localhost` w emulatorze to sam emulator. Na Windows zezwól Node.js na ruch w sieci prywatnej (okno zapory przy pierwszym `npm start`). HTTP bez TLS działa w modelu Stage bez dodatkowej konfiguracji, wystarczy uprawnienie `INTERNET`.

### Lokalizacja i trasa

Lokalizacja z GPS nie jest jeszcze podpięta (#10, #48). Do tego czasu przewodnik na trasie demo (Barbakan → Wawel, 1,5 km) pokazuje strona debug `GuideDebugPage` (odtwarzanie `fixtures/demo-route-krakow.json`, oznaczone jako SYMULACJA). Punkt w panelu lokalizacji emulatora (*Location*) ustawia się ręcznie. Trasa w GPX: `fixtures/demo-route-krakow.gpx`.

## Serwer (`server/`)

```sh
cd server
cp .env.example .env     # opcjonalne; bez niego serwer działa z szablonami i bez głosu
npm start                # port 8787; w logu adresy LAN dla emulatora
npm test                 # testy bez sieci
```

Sprawdzenie: `http://localhost:8787/v1/health` i `http://localhost:8787/v1/pois?lat=50.0617&lon=19.9373&radius=150`. Szczegóły endpointów: [`server/README.md`](server/README.md), [`docs/CONTRACTS.md`](docs/CONTRACTS.md).

### Bielik (tekst przewodnika)

Bez LLM serwer zwraca segmenty z szablonów (`origin: "template"`). Dwie drogi, to samo API Ollamy:

- **Modal (tak działa demo):** `pip install modal`, `python -m modal setup`, `python -m modal deploy server/modal/bielik_ollama.py`. W `server/.env`: `OLLAMA_URL` z adresem z `modal deploy`, `LLM_MODEL=bielik-4.5b-v3.0-instruct:Q8_0`, `MODAL_KEY` i `MODAL_SECRET` (token z *Settings → Proxy Auth Tokens*). Szczegóły i koszty: [`server/modal/README.md`](server/modal/README.md). Na demo: `BIELIK_MIN_CONTAINERS=1 python -m modal deploy …` (bez zimnego startu ~90 s).
- **Lokalnie:** Ollama i model `speakleash/Bielik-4.5B-v3.0-Instruct-GGUF` (`ollama create bielik-4.5b-v3.0-instruct:Q8_0 -f Modelfile`; Modelfile z szablonem ChatML jak w `server/modal/bielik_ollama.py`), w `.env` `OLLAMA_URL=http://localhost:11434`, `MODAL_KEY` pusty. Tylko wtedy przetwarzanie jest lokalne.

### Głos

- `TTS_PROVIDER=elevenlabs` + `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID` (darmowy plan: tylko wbudowane głosy przez API, 10 000 znaków na miesiąc), zapasowo Piper.
- `TTS_PROVIDER=piper`: Piper offline (`PIPER_BIN`, `PIPER_VOICE`, `FFMPEG_BIN`; instalacja w [`server/README.md`](server/README.md)).
- `npm run tts-smoke` sprawdza oba, `npm run tts-smoke voices` pokazuje polskie głosy na koncie.

### Przed demo

```sh
npm run warm -- --dry-run    # plan i szacunek znaków ElevenLabs
npm run warm -- --limit 5    # tekst i audio dla 5 przystanków trasy demo do cache
npm run eval                 # ewaluacja modelu (~10 min GPU), wyniki w server/eval/results/
```

## Tryb offline (bez serwera)

Z pustym `API_BASE_URL`:
- działa: lista zabytków z dołączonych danych (`rawfile/pois-krakow.json`, trasa demo), silnik przewodnika, teksty z szablonów (pierwsze zdania artykułu z Wikipedii), wszystkie ekrany;
- nie działa: tekst z Bielika, głos (bez audio, sam tekst), zabytki spoza trasy demo, łącze z zegarkiem.

## Dane i licencje

Opisy miejsc pochodzą z polskiej Wikipedii (MediaWiki GeoSearch API), licencja CC BY-SA 4.0; każdy segment linkuje artykuł źródłowy. Sygnały ważności i rodzaju miejsca z Wikidata. Dane demo: `fixtures/`, generowane przez `tools/gen_fixtures.py` tymi samymi regułami co serwer. Model: Bielik-4.5B-v3.0-Instruct (SpeakLeash, ACK Cyfronet AGH), Apache 2.0.
