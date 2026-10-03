// Mirrors `Poi` in docs/CONTRACTS.md.
export interface Poi {
  id: string;                  // "plwiki:<pageid>", stable
  name: string;
  summary: string;             // article intro: source of facts for AI and templates
  lat: number;
  lon: number;
  kind: string | null;         // "building" | "landmark" | null
  wikidataId: string | null;
  imageUrl: string | null;
  sourceUrl: string;           // article link (CC BY-SA 4.0), shown in UI
  distanceM?: number;          // only in /v1/pois responses and PoiRepository results
}
