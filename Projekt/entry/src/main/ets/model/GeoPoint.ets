export interface GeoPoint {
  lat: number;
  lon: number;
}

export interface GeoFix extends GeoPoint {
  accuracyM: number;
  t: number; 
}
