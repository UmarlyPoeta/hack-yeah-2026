import { GeoPoint } from '../model/GeoPoint';

// Conventions used across the guide engine:
//   distances in metres, angles in degrees,
//   bearings measured from north (0) clockwise (east = 90).

export const EARTH_RADIUS_M: number = 6371000;

export function toRad(deg: number): number {
  return deg * Math.PI / 180;
}

export function toDeg(rad: number): number {
  return rad * 180 / Math.PI;
}

// Maps any angle onto 0..360. JavaScript's % keeps the sign of the dividend
// (-30 % 360 === -30), so we add 360 before the second modulo.
export function normalizeDeg(deg: number): number {
  return ((deg % 360) + 360) % 360;
}

// Great-circle distance (haversine formula). Accurate to well under a metre
// at city scale, which is far below GPS noise.
export function distanceM(a: GeoPoint, b: GeoPoint): number {
  const phi1 = toRad(a.lat);
  const phi2 = toRad(b.lat);
  const dPhi = phi2 - phi1;
  const dLambda = toRad(b.lon - a.lon);
  const h = Math.sin(dPhi / 2) * Math.sin(dPhi / 2)
    + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) * Math.sin(dLambda / 2);
  // min() guards against h drifting a hair above 1 from floating-point error
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(Math.min(1, h)));
}

// Initial bearing from a to b, 0..360.
export function bearingDeg(a: GeoPoint, b: GeoPoint): number {
  const phi1 = toRad(a.lat);
  const phi2 = toRad(b.lat);
  const dLambda = toRad(b.lon - a.lon);
  const y = Math.sin(dLambda) * Math.cos(phi2);
  const x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLambda);
  return normalizeDeg(toDeg(Math.atan2(y, x)));
}

// How far to turn from heading `from` to face `to`, in -180..180.
// Positive = turn right (clockwise), negative = turn left.
// Example: from 350 to 10 is +20, not -340.
export function angleDiffDeg(from: number, to: number): number {
  return normalizeDeg(to - from + 180) - 180;
}

// Where a point lies relative to someone walking with a given heading.
export interface RelativePosition {
  distanceM: number;
  bearingDeg: number;  // absolute bearing from the walker to the point
  alongM: number;      // > 0 ahead, < 0 behind
  crossM: number;      // > 0 to the right, < 0 to the left
}

export function relativePosition(from: GeoPoint, headingDeg: number, to: GeoPoint): RelativePosition {
  const d = distanceM(from, to);
  const bearing = bearingDeg(from, to);
  const delta = toRad(angleDiffDeg(headingDeg, bearing));
  const result: RelativePosition = {
    distanceM: d,
    bearingDeg: bearing,
    alongM: d * Math.cos(delta),
    crossM: d * Math.sin(delta)
  };
  return result;
}
