# guide-lab

Pure guide-engine logic (models, geo, parsers, later MotionTracker / Itinerary / Planner) written in
**ArkTS-compatible TypeScript** and tested in Node, so it can be developed on Linux without DevEco Studio.

```bash
cd guide-lab
npm install
npm run check      # strict type check + tests
```

## Porting to the DevEco project
Copy `src/**/*.ts` to `entry/src/main/ets/` keeping the folders (`model/`, `guide/`, `data/`) and rename
`.ts` → `.ets`. Imports have no file extension, so they work unchanged. Then run `devecocli check lint`
(ArkTS linter) and port the tests in `test/` to Hypium (`entry/src/test/`).

Rules followed so the code ports cleanly: no `any`/`unknown`, every object literal has a declared type,
no destructuring or object spread, no index access (`obj['x']`), types with a position extend `GeoPoint`
(ArkTS has no structural typing), time is always a parameter (no `Date.now()` in logic).
Only the tests use Node APIs (`node:fs`, `node:test`); `src/` does not.

## What is here

| File | Role |
|---|---|
| `src/guide/geo.ts` | distance, bearing, along/cross |
| `src/guide/MotionTracker.ts` | fixes → speed, heading, MOVING/STOPPED |
| `src/guide/Itinerary.ts` | what is ahead, ETA, side, passed/missed |
| `src/guide/Stops.ts` | grouping places into stops, relative importance threshold |
| `src/guide/Templates.ts` | Polish narration without AI |
| `src/guide/NarrationPlanner.ts` | what to say, when, how long |
| `src/guide/GuideDirector.ts` | events in, actions out |
| `src/viewmodel/WalkController.ts` | ports to server/player/clock, screen state |


The same files live in `Projekt/entry/src/main/ets/` as `.ets`; keep both in sync (copy, rename).
