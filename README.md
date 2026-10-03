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
