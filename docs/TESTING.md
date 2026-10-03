# Strategia testów

Jury pyta o testy kluczowych scenariuszy i o zachowanie przy błędach (API, timeouty, brak danych, zły output modelu). Testujemy więc **logikę przewodnika, kontrakty i ścieżki awaryjne**.

## Poziomy

| Poziom | Narzędzie | Co | Gdzie | Kto |
|---|---|---|---|---|
| Unit: przewodnik | Hypium (`entry/src/test`) | `geo`, `MotionTracker`, `Itinerary`, `NarrationPlanner`, `GuideDirector`, `Templates` | lokalnie w DevEco | P2 |
| Unit: sesja | Hypium | przejścia `WalkSession` | lokalnie | P1 |
| Unit: serwer | `node --test` | parser GeoSearch, filtr, cache, prompt builder, walidator, TTS providers (mock), fallbacki | dowolny OS, **bez sieci** | P3, P4 |
| Kontrakt | `node --test` | odpowiedzi `/v1/*` zgodne z `CONTRACTS.md` | dowolny OS | P3, P4 |
| Ewaluacja AI | `server/eval/` | 10 POI × 3 typy segmentów: % przechodzących walidację, czas generacji, ocena 1–5 | z Ollamą | P4 |
| E2E | checklista niżej | pełny spacer na emulatorze | DevEco | P1, P5 |

Testy serwera nie wołają sieci: Wikipedia jest nagrana w `server/test/fixtures/`, a Ollama i ElevenLabs są mockowane.

## Scenariusze przewodnika (Hypium, na `fixtures/`)

1. **Cała trasa demo** (replay `demo-route-krakow.json`): sekwencja zaczyna się od `WELCOME`, każdy POI ma co najwyżej jeden `ARRIVAL`, a `BRIDGE` występuje tylko między kolejnymi `ARRIVAL`.
2. **Kolejność:** POI pojawiają się w kolejności `along` (Barbakan przed Bramą Floriańską przed Mariackim).
3. **Dwa zabytki < 20 m od siebie:** brak `BRIDGE`, a drugi `APPROACH` ma wariant „Tuż obok”.
4. **Histereza:** 20 s stania na granicy 35/50 m daje dokładnie 1 `ARRIVAL`.
5. **Zatrzymanie:** 10 s z prędkością ~0 po `ARRIVAL` daje `DEEP_DIVE_OFFER`; ruch przed 8 s go nie wywołuje.
6. **Budżet:** gdy ETA do następnego wynosi 20 s, `ARRIVAL` ma ≤ 40 słów; przy 120 s ma ≤ 120.
7. **Brak przerywania:** segment o wyższym priorytecie startuje dopiero po `durationMs` bieżącego (albo końcu zdania).
8. **Przeterminowanie:** `APPROACH` do POI, który został minięty, nie jest odtwarzany.
9. **Szum GPS:** fix z `accuracyM` 150 m albo skok 300 m nie zmienia `upcoming` ani nie daje zdarzeń.
10. **Brak POI:** brak segmentów poza `WELCOME`, bez wyjątków.

`WalkSession`: każde przejście z diagramu (`ARCHITECTURE.md` §5), w tym `WALKING → PAUSED` po `onBackground` i `ACQUIRING → ERROR(NO_FIX)` po 15 s.

## Scenariusze serwera

Walidator: cytat spoza źródła → odrzucone; rok spoza źródła → odrzucone; poprawny tekst → przyjęty.
LLM: timeout / błąd / nie-JSON → retry, potem szablon + `warnings`.
TTS: błąd ElevenLabs → Piper → `tts_fallback_piper`; oba padną → `audioUrl: null` + `tts_unavailable`.
Cache: drugi identyczny request nie woła LLM ani TTS.

## E2E: checklista na emulatorze (przed nagraniem demo)

- [ ] Czysta instalacja `.hap` → start **bez żadnego okienka uprawnień**.
- [ ] `hdc shell bm dump -n <bundle>`: brak uprawnień lokalizacji w `requestPermissions`.
- [ ] Klik `LocationButton` + GPS emulatora na Barbakan → `WALKING`, słychać `WELCOME`.
- [ ] Przesuwanie GPS wzdłuż trasy → `APPROACH` → `ARRIVAL` → `BRIDGE` → kolejny `APPROACH`, mowa bez nakładania się.
- [ ] Zatrzymanie przy Sukiennicach → „Opowiedz więcej”, a po akceptacji `DEEP_DIVE`.
- [ ] Wyjście do ekranu głównego i powrót → `PAUSED`, narracja zatrzymana, brak aktualizacji pozycji w logach.
- [ ] Serwer wyłączony → POI z fixtures, szablony, etykieta „szablon”.
- [ ] Ollama wyłączona → szablon tekstu, ale z głosem (TTS dalej działa).
- [ ] `TTS_PROVIDER=piper` → głos Pipera, etykieta głosu się zmienia.
- [ ] Brak sieci w emulatorze → jak przy wyłączonym serwerze, bez crasha.
