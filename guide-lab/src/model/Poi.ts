import { GeoPoint } from './GeoPoint';

export enum PoiRole {
  SIGHT = 'sight',   // a place you can stand next to and talk about
  AREA = 'area'      // a street, square or district: never an ARRIVAL, only background
}

// A place the guide can talk about. Mirrors Poi in docs/CONTRACTS.md.
export interface Poi extends GeoPoint {
  id: string;                // "plwiki:<pageid>"
  name: string;
  summary: string;           // Wikipedia intro, the only source of facts
  kind: string | null;       // "building" | "landmark" | null
  wikidataId: string | null;
  imageUrl: string | null;
  sourceUrl: string;         // shown in the UI (CC BY-SA 4.0)
  importance: number;        // 0..1, from the number of Wikipedia language versions
  role: PoiRole;
  partOfId: string | null;   // id of the Poi this one belongs to (gallery inside a hall)
  distanceM?: number;        // only set in /v1/pois responses
}
