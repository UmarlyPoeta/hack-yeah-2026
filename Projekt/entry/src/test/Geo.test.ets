import { describe, it, expect } from '@ohos/hypium';
import { GeoPoint } from '../main/ets/model/GeoPoint';
import { angleDiffDeg, bearingDeg, distanceM, normalizeDeg, relativePosition, RelativePosition } from '../main/ets/guide/geo';

function pt(lat: number, lon: number): GeoPoint {
  const p: GeoPoint = { lat: lat, lon: lon };
  return p;
}

function near(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

// both taken from fixtures/pois-krakow.json
const BARBAKAN: GeoPoint = pt(50.065514, 19.941617);
const SUKIENNICE: GeoPoint = pt(50.061667, 19.937222);

export default function geoTest() {
  describe('geo', () => {
    it('distanceBarbakanSukiennice', 0, () => {
      expect(near(distanceM(BARBAKAN, SUKIENNICE), 530, 5)).assertTrue();
    });

    it('distanceOneDegreeLatitude', 0, () => {
      expect(near(distanceM(pt(50, 20), pt(51, 20)), 111195, 10)).assertTrue();
    });

    it('distanceZeroAndSymmetric', 0, () => {
      expect(distanceM(BARBAKAN, BARBAKAN)).assertEqual(0);
      expect(near(distanceM(BARBAKAN, SUKIENNICE), distanceM(SUKIENNICE, BARBAKAN), 1e-6)).assertTrue();
    });

    it('bearingCardinalDirections', 0, () => {
      expect(near(bearingDeg(pt(50, 20), pt(51, 20)), 0, 0.01)).assertTrue();
      expect(near(bearingDeg(pt(50, 20), pt(50, 20.01)), 90, 0.01)).assertTrue();
      expect(near(bearingDeg(pt(50, 20), pt(49, 20)), 180, 0.01)).assertTrue();
      expect(near(bearingDeg(pt(50, 20), pt(50, 19.99)), 270, 0.01)).assertTrue();
    });

    it('normalizeDegWraps', 0, () => {
      expect(normalizeDeg(-30)).assertEqual(330);
      expect(normalizeDeg(370)).assertEqual(10);
      expect(normalizeDeg(360)).assertEqual(0);
    });

    it('angleDiffCrossesNorth', 0, () => {
      expect(near(angleDiffDeg(350, 10), 20, 1e-9)).assertTrue();
      expect(near(angleDiffDeg(10, 350), -20, 1e-9)).assertTrue();
      expect(near(angleDiffDeg(0, 270), -90, 1e-9)).assertTrue();
    });

    it('relativePositionAhead', 0, () => {
      const r: RelativePosition = relativePosition(pt(50, 20), 0, pt(50.0009, 20));
      expect(near(r.alongM, 100, 1)).assertTrue();
      expect(near(r.crossM, 0, 0.5)).assertTrue();
    });

    it('relativePositionSides', 0, () => {
      const walker: GeoPoint = pt(50, 20);
      expect(relativePosition(walker, 0, pt(50, 20.0014)).crossM > 90).assertTrue();   // east = right
      expect(relativePosition(walker, 0, pt(50, 19.9986)).crossM < -90).assertTrue();  // west = left
      expect(relativePosition(walker, 0, pt(49.9991, 20)).alongM < -90).assertTrue();  // south = behind
    });

    it('relativePositionDependsOnHeading', 0, () => {
      // walking east, a point to the north is on the left
      const r: RelativePosition = relativePosition(pt(50, 20), 90, pt(50.0009, 20));
      expect(r.crossM < -90).assertTrue();
    });
  });
}
