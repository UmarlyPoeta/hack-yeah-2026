# Jak pracujemy (5 osób, ~20 h)

Szczegółowy opis każdej roli: [`ROLES.md`](ROLES.md). Backlog: [`../tools/issues.md`](../tools/issues.md) (zakładany na GitHubie skryptem `tools/create_issues.py`).

## Role w skrócie

| Osoba | Rola | Code owner |
|---|---|---|
| **P1** | Platforma i integracja (lead) | projekt DevEco, `session/`, `location/`, podpisywanie, release, merge do `main` |
| **P2** | Silnik przewodnika | `model/`, `guide/`, `viewmodel/`, testy Hypium przewodnika |
| **P3** | Dane, serwer bazowy, klienci HTTP | `server/` (szkielet, `/v1/pois`, cache), `data/PoiRepository.ets`, `data/SegmentService.ets`, `fixtures/`, `tools/`, README |
| **P4** | AI i głos | `server/` (`/v1/segment`, LLM, TTS, walidator, warm, eval), sekcja AI w `AI_WORKFLOW.md` |
| **P5** | UI/UX, odtwarzacz i demo | `pages/`, `components/`, `audio/NarratorPlayer.ets`, demo, redakcja `AI_WORKFLOW.md` |

## Kamienie milowe (CEST)

| Milestone | Kiedy | Definicja „gotowe” |
|---|---|---|
| **M0 Fundament** | sob 18:00 | projekt buduje się i startuje na emulatorze; spike'i lokalizacji, sieci i dźwięku rozstrzygnięte; `server/` odpowiada na `/v1/health`; Ollama z Bielikiem odpowiada |
| **M1 Draft E2E** | sob 20:00 | **koncepcja zamrożona.** `LocationButton` → pozycja → POI z fixtures → `ARRIVAL` z szablonu na ekranie |
| **M2 Feature complete** | ndz 04:00 | sekwencja segmentów z AI i głosem, deep dive, wszystkie ekrany, testy zielone, E2E checklista przechodzi |
| **M3 Zgłoszenie** | ndz, 2 h przed deadlinem | podpisany `.hap` w Release, demo nagrane, README, `AI_WORKFLOW.md`, architektura |

Po M2 **zero nowych funkcji**.

## Git i PR-y

- `main` zawsze się buduje i działa. Bezpośrednio do `main` trafia tylko drobna dokumentacja.
- Gałąź: `<nr-issue>-krotki-opis`. PR: tytuł `#<nr> Opis`, w treści `Closes #<nr>`, wypełniony template, mały zakres.
- Review: 1 osoba. Merge: **P1** (squash), po zielonych testach.
- Commituj często i opisowo, bo historia commitów jest oceniana.
- **Nigdy** nie commituj: `.env`, kluczy (ElevenLabs!), keystore `.p12`, profili, `build/`, `node_modules/`, plików audio z cache.

## AI_WORKFLOW.md (obowiązkowe)

Każdy, kto używa agenta AI, dopisuje w PR 1–3 wiersze do tabeli logu: narzędzie, prompt w skrócie, co powstało i jak to zweryfikował. P5 redaguje całość przed M3.

## Komunikacja

„Blokuje mnie X” piszesz od razu w issue. Zmiany kontraktu najpierw idą jako komentarz i wymagają zgody drugiej strony. Stand-up co 2 h, 5 minut.
