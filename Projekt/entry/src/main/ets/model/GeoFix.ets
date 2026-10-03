// One location reading. Mirrors `GeoFix` in docs/CONTRACTS.md.
export interface GeoFix {
  lat: number;          // WGS84
  lon: number;
  accuracyM: number;
  t: number;            // ms, monotonic clock
}
