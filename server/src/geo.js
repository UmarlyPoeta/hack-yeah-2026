const EARTH_RADIUS_M = 6371000;

export function haversineM(lat1, lon1, lat2, lon2) {
  const rad = Math.PI / 180;
  const dp = (lat2 - lat1) * rad;
  const dl = (lon2 - lon1) * rad;
  const h = Math.sin(dp / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dl / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

// Grid cell of roughly `sizeM` x `sizeM` metres, used as a cache key.
export function gridCell(lat, lon, sizeM = 100) {
  const dLat = sizeM / 111320;
  const dLon = sizeM / (111320 * Math.cos(lat * Math.PI / 180));
  const i = Math.floor(lat / dLat);
  const j = Math.floor(lon / dLon);
  return { key: `${i}:${j}`, lat: (i + 0.5) * dLat, lon: (j + 0.5) * dLon };
}
