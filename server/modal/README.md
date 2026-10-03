# Bielik na Modalu

Bielik-4.5B-v3.0-Instruct (GGUF Q8_0 z `speakleash/Bielik-4.5B-v3.0-Instruct-GGUF`) w kontenerze Ollamy na GPU w [Modal](https://modal.com). Wystawia **niezmienione API Ollamy** (`/api/chat`, `/api/tags`, …), więc `server/` używa go jak lokalnej Ollamy: zmienia się tylko `OLLAMA_URL` i dochodzą dwa nagłówki autoryzacji.

## Co robi Bielik w projekcie

Pisze tekst segmentów `WELCOME`, `ARRIVAL`, `BRIDGE`, `DEEP_DIVE` w `POST /v1/segment` (#18). Dostaje prompt + tekst źródłowy POI z Wikipedii, zwraca JSON `{title?, text, claims[{text, quote}]}` wymuszony przez `format` (JSON Schema). `APPROACH`/`MISSED` są z szablonów, głos robi TTS. Do Modala trafia tylko prompt o zabytku (bez lokalizacji i danych użytkownika).

## Wdrożenie (jednorazowo)

```bash
pip install modal
python -m modal setup                        # logowanie w przeglądarce
python -m modal deploy server/modal/bielik_ollama.py
```

Pierwsze wdrożenie buduje obraz: instaluje Ollamę, pobiera GGUF (~5 GB) i rejestruje model. Trwa kilka minut, kolejne wdrożenia używają cache. Na końcu `modal deploy` wypisuje URL, np. `https://<workspace>--bielik-ollama-serve.modal.run`.

**Token autoryzacji:** endpoint ma `requires_proxy_auth=True`, więc bez nagłówków `Modal-Key` / `Modal-Secret` odpowiada 401. Token tworzysz w panelu Modala: *Settings → Proxy Auth Tokens → New token*. Wartości wpisz do `server/.env` (`MODAL_KEY`, `MODAL_SECRET`), nigdy do repo.

## `server/.env`

```
OLLAMA_URL=https://<workspace>--bielik-ollama-serve.modal.run
LLM_MODEL=bielik-4.5b-v3.0-instruct:Q8_0
MODAL_KEY=wk-...
MODAL_SECRET=ws-...
```

`LlmProvider` w `server/` musi dodać do każdego zapytania nagłówki `Modal-Key: $MODAL_KEY` i `Modal-Secret: $MODAL_SECRET`.

## Test i pomiar (#6)

```bash
BIELIK_URL=https://... MODAL_KEY=wk-... MODAL_SECRET=ws-... python server/modal/smoke_test.py --runs 3
```

Sprawdza `/api/version` i `/api/tags`, potem 3× `ARRIVAL` ~100 słów dla Kamienicy Czyncielów z `fixtures/pois-krakow.json`. Pokazuje czas (pierwszy = zimny start), tokeny/s, zgodność ze schematem i czy cytaty oraz liczby są w źródle (te same reguły co walidator z #18).

### Wyniki (2026-10-03, T4, Ollama 0.35.1, Q8_0, `ARRIVAL` Kamienica Czyncielów)

| | zimny start | ciepły |
|---|---|---|
| czas całego zapytania | ~86 s (10 s kontener + 40 s ładowanie modelu + generacja) | 9,7–11,6 s |
| szybkość generacji | 20 tok/s | 39 tok/s |
| tokeny odpowiedzi (tekst + claims) | 493 | 355–430 |

- Schemat JSON: 4/4 OK. Długość tekstu 47–60 słów przy prośbie o ~100 (do dostrojenia promptem w #18).
- Liczby i lata w tekście: wszystkie występują w źródle. Cytaty: 1–2 z 3 nie są dosłowne (model lekko je parafrazuje), więc walidator z #18 jest potrzebny.
- Drobne przekłamania słów („sklep galaretowy” zamiast „galanteryjny”). `temperature` 0,2.
- Wniosek dla prefetchu (#20): ciepły `ARRIVAL` ~10 s mieści się w ETA; po przerwie > 2 min pierwsze zapytanie trwa ~1,5 min, więc przed spacerem trzeba „obudzić” model (np. `GET /api/version` + 1 zapytanie przy starcie sesji) albo użyć `BIELIK_MIN_CONTAINERS=1`.
- **Szablon czatu:** Bielik v3 używa ChatML (`<|im_start|>`). Szablon w stylu Llama 3 z karty modelu na HF jest błędny: z nim odpowiedzi były ucinane, a część zapytań kończyła się HTTP 500.

## Koszt i zimny start

- GPU: domyślnie `T4`, najtańsze na Modalu (ok. 0,6 USD/h, tylko gdy kontener działa). Zmiana: `BIELIK_GPU=L4 modal deploy ...`. Model Q8_0 zajmuje ~5 GB VRAM. Maksymalnie 1 kontener naraz.
- Kontener gaśnie po 2 min bezczynności, więc płacimy tylko za czas pracy. Pierwsze zapytanie po przerwie czeka na zimny start (start kontenera + załadowanie modelu do GPU).
- **Przed demo:** `BIELIK_MIN_CONTAINERS=1 python -m modal deploy server/modal/bielik_ollama.py` trzyma jeden ciepły kontener (płatny także bez ruchu). Po demo wdróż ponownie bez tej zmiennej.
- Limit wydatków: w panelu Modala *Settings → Usage & Billing* ustaw miesięczny budżet workspace.
- Logi: `python -m modal app logs bielik-ollama`. Zatrzymanie: `python -m modal app stop bielik-ollama`.
