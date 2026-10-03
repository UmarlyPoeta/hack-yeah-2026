import { GeoPoint } from './GeoPoint';

// A place the guide can talk about. Mirrors Poi in docs/CONTRACTS.md.
export interface Poi extends GeoPoint {
  id: string;                // "plwiki:<pageid>"
  name: string;
  summary: string;           // Wikipedia intro, the only source of facts
  kind: string | null;       // "building" | "landmark" | null
  wikidataId: string | null;
  imageUrl: string | null;
  sourceUrl: string;         // shown in the UI (CC BY-SA 4.0)
  distanceM?: number;        // only set in /v1/pois responses
}
