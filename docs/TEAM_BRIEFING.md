# HackYeah 2026 — Huawei / OpenHarmony Challenge: briefing drużyny

Źródła: `hackyeah2026-challenge/` (README, FAQ, hackathon_challenge.md, prezentacja z warsztatów, szablony, skille). Autorytatywny regulamin: https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/hackathon_challenge.md

## 1. Zadanie w jednym zdaniu

Zbudować **innowacyjną aplikację albo „system feature”** (instalowalny komponent, bez modyfikacji samego OS) na urządzenie mobilne z **OpenHarmony / HarmonyOS / Oniro**, **API ≥ 20**, działającą na emulatorze lub urządzeniu, która **realnie używa możliwości platformy**.

Musi się wpisywać (wyraźnie prowadzić) w jeden z trzech tematów — najlepiej łączyć dwa, jeśli połączenie ma sens:

| Temat | Hasło | Przykłady |
|---|---|---|
| **Intelligent Experiences** | produkt mądrzejszy | agenci, świadomość kontekstu, personalizacja, on-device AI |
| **Spatial Experiences** | interakcja ze światem fizycznym | spatial UI, 3D, sensory, pozycjonowanie, nowe formy interakcji |
| **Human-Centric Technology** | technologia dla ludzi | dostępność, digital wellbeing, inclusive design, edukacja, kultura |

Trzy ścieżki: **A** natywna ArkTS + ArkUI (zalecana), **B** React Native for OpenHarmony (musi być target OHOS, sam Android/iOS/web się nie liczy), **C** system feature (np. ArkTS UI + C/C++ przez NDK/Node-API).

## 2. Jak oceniają (to dyktuje wszystkie decyzje)

| Kryterium | Waga | Co faktycznie punktuje |
|---|---|---|
| Oryginalność | 20% | nowy pomysł lub świeże ujęcie; łączenie tematów = plus |
| Użyteczność | 20% | konkretny użytkownik + konkretny problem; **wąskie i działające > szerokie na slajdach** |
| Wykonanie techniczne | 20% | działa jak opisano, sensowna architektura, obsługa błędów (timeouty, brak danych, zły output modelu), **jakieś testy**, brak sekretów, minimalne uprawnienia |
| Użycie możliwości platformy | 20% | system services / API / Kity OHOS. Apka, która działa bez zmian na każdym OS = niska ocena |
| Jakość demo | 10% | działa na emulatorze, jasne co zbudowano na hackathonie, symulacje jawnie oznaczone |
| Reprodukowalność | 10% | ktoś obcy zbuduje z README; wersje SDK; **historia commitów pokazuje postęp**; AI_WORKFLOW.md |

Repo może przejść **automatyczny pre-review** — README, AI_WORKFLOW.md, czysty .gitignore i brak sekretów to „łatwe punkty, które najłatwiej stracić”.

## 3. Wymagane deliverables (checklista)

- [ ] publiczne repo z kodem
- [ ] instrukcja setup / build / install / launch (reprodukowalna z czystego checkoutu)
- [ ] działający **`.hap`** (podpisany)
- [ ] krótkie **nagranie demo** (nagrywamy sami — **przed** końcem czasu, nie po)
- [ ] zwięzły opis architektury i implementacji
- [ ] **`AI_WORKFLOW.md`** — obowiązkowe, bo używamy agentów (narzędzia, modele, skille, MCP, główne prompty, workflow, jak weryfikowaliśmy, porażki, lekcje)
- [ ] jeśli produkt ma funkcję AI: model/usługa, przepływ inferencji, dane i prywatność, ograniczenia, fallback, walidacja

## 4. Środowisko — NAJWIĘKSZE RYZYKO

| | DevEco Studio (domyślna ścieżka) | Oniro App Builder / Oniro IDE (VS Code) |
|---|---|---|
| OS | **Windows** 10/11 lub **macOS Apple Silicon** | **Windows lub Linux** |
| Emulator | DevEco Emulator: telefon/tablet/2in1/TV/zegarek, **sensory, GPS**, orientacja | QEMU, OpenHarmony 6.1 / **API 23**, tylko jeden profil, **brak sensorów i GPS** |
| Dojrzałość | stabilne | w rozwoju, znane bugi (patrz FAQ) |

Nigdzie nie ma: kamery, NFC, BT z realnym sprzętem, SIM, biometrii, testów distributed. Mentorzy mają **fizyczne urządzenia na miejscu**.

**Wniosek:** potrzebujemy przynajmniej **jednej maszyny z Windows (albo Maca M-series) jako „stacji build + demo”** z DevEco Studio. Linux (Fedora) → Oniro App Builder; nadaje się do pisania kodu i budowania, ale demo z sensorami/GPS tylko na DevEco.

### Ustawienia SDK (z README/FAQ)
- DevEco: **Compatible SDK = 6.0.0 (API 20)**, `compileSdkVersion` = API 23, `targetSdkVersion` = API 24.
- Oniro emulator: SDK 6.1, projekty z `--sdk 23`, nie polegać na API-24-only.
- **Region DevEco → CN** (`country.region.xml`), inaczej emulator tylko zegarków.
- devecocli **przypięte do 1.3.4** + patche (`scripts/apply-devecocli-patches.mjs`); nie robić `devecocli update`.
- Node ≥ 22 (DevEco ma własne starsze Node — pilnować kolejności w PATH).
- `devecocli signature generate` nie działa poza Chinami → podpisywanie przez DevEco Studio (File → Project Structure → Signing Configs). Debug build z IDE nie wymaga konta.
- **Nigdy nie commitować keystore (.p12), certów, profili ani haseł.**

## 5. Proponowany podział ról (5 osób)

| Rola | Odpowiada za | Pierwsze zadanie (godzina 0–2) |
|---|---|---|
| **1. Tech lead / integrator** | repo, gałęzie, merge do `main`, build pipeline, podpisywanie, emulator, finalny `.hap` | stacja DevEco (Windows), szablon Hackathon Template, pierwszy „hello” `.hap` na emulatorze |
| **2. ArkUI dev (UI/UX)** | ekrany, nawigacja, stan (@State/@Prop/@Link, MVVM) | szkielet ekranów głównego flow |
| **3. Platform-capability dev** | integracja z Kitem/system service, który jest sercem pomysłu (uprawnienia, błędy, logi) | spike: czy wybrane API działa na emulatorze — **to decyduje o wykonalności** |
| **4. AI / logika domenowa** | model/agent (lokalny lub zdalny), fallbacki, testy logiki | spike modelu + kontrakt danych z UI |
| **5. Product / demo / docs** | pitch, user story, README, ARCHITECTURE, AI_WORKFLOW.md, scenariusz i nagranie demo, pilnowanie czasu | wypełnić `HACKATHON_BRIEF.md`, zebrać prompty od wszystkich od początku |

Wszyscy: commitujemy często, małe kroki, gałąź na feature, `main` zawsze buildowalny. Każdy loguje istotne prompty do AI_WORKFLOW.md (lub do wspólnej notatki, którą #5 przenosi).

## 6. Plan czasowy (24h — dostosować do oficjalnej agendy)

1. **0–2h:** środowisko na wszystkich maszynach; pierwszy `.hap` zainstalowany na emulatorze (zalecenie Huawei: w ciągu pierwszych godzin). Decyzja o pomyśle i *jednej* kluczowej capability.
2. **2–4h:** spike'i ryzyk (API platformy, AI). Jeśli coś nie działa na emulatorze — zmiana planu TERAZ, nie o 3 w nocy.
3. **4–14h:** pionowy wycinek end-to-end (jeden flow działa w całości), potem dopiero rozszerzanie.
4. **14–18h:** obsługa błędów, testy kluczowych scenariuszy, uprawnienia minimalne, README na bieżąco.
5. **18–20h:** **feature freeze, nagranie demo**, podpisany `.hap`, release w repo.
6. **20h–koniec:** dokumentacja, AI_WORKFLOW.md, architektura, pitch; bufor na awarie.

## 7. Jak myśleć o pomyśle (filtr przed decyzją)

Każdy pomysł przepuszczamy przez 5 pytań:
1. **Kto** konkretnie tego używa i jaki ma problem? (1 zdanie)
2. **Jaka capability OHOS** jest w centrum i czy **działa na emulatorze**? (jeśli nie — czy mentorzy mają urządzenie?)
3. Czy apka byłaby **identyczna na Androidzie**? Jeśli tak → słabo na 20% kryterium platformy.
4. Czy da się pokazać **jeden flow end-to-end w 90 sekund demo**?
5. Który temat **prowadzi**, a który jest drugim (bonus za sensowne połączenie)?

Rzeczy działające na emulatorze, na których da się zbudować wyróżnik: powiadomienia, **widgety (service cards)**, rozszerzone uprawnienia (np. notification listener), aplikacje systemowe (tylko emulator), internet, a w DevEco także **sensory (akcelerometr, żyroskop), GPS**, profile wielu urządzeń, symulacja zegarka (tętno, kroki).

Pułapki: wymyślanie API z pamięci (używać skilli `hmos-arkts-knowledge-retriever`, `devecocli docs search`), Kity „HarmonyOS-only” na targecie OpenHarmony, rzeczy wymagające kamery/BT/NFC/biometrii bez fizycznego urządzenia.

## 8. Narzędzia AI, które dostajemy

Skille (instalowane przez `INSTALLATION_PROMPT.md`, Windows): `ohos-app-scaffold`, `ohos-app-dev` (lint/build/run/logi/UI), `ohos-system-app-dev` (preflight uprawnień systemowych), `ohos-system-dev`, `conductor-dev`, `hmos-arkts-knowledge-retriever`, `hmos-arkui-develop-skill`, `hmos-arkui-scenario-development`, `hmos-arkui-mvvm-pattern` + skill z `devecocli init --skill`. Na Linuksie zamiast tego: [Oniro Agent Skills](https://github.com/eclipse-oniro4openharmony/agent-skills) (używają `oniro-app`).

Szablon **Hackathon Template** daje gotowe `AGENTS.md` / `CLAUDE.md`, `HACKATHON_BRIEF.md`, `AI_WORKFLOW.md`, `hackathon-resources/`. Wybieramy go zamiast Conductor, chyba że ktoś chce orkiestracji Conductorem.

## 9. Linki

- Challenge repo: https://github.com/onirodeveloper/hackyeah2026-challenge
- Oniro docs / pierwsza apka: https://docs.oniroproject.org/application-development/create-your-first-app/
- Codelaby: https://docs.oniroproject.org/application-development/codeLabs/
- Sample app Huawei (biblioteka komponentów): https://github.com/onirodeveloper/harmonyos_samples
- Oniro App Builder / IDE: https://github.com/eclipse-oniro4openharmony
- RNOH: https://gitcode.com/CPF-RN/ohos_react_native/tree/0.77-main/docs/en
- Teaser Huawei: sobota 12:00–12:45, ścieżka Softskills
