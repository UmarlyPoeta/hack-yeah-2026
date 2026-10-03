import { describe, it, expect } from '@ohos/hypium';
import { MotionTracker } from '../main/ets/guide/MotionTracker';
import { Itinerary, ItineraryView, Side, UpcomingPoi } from '../main/ets/guide/Itinerary';
import { Poi } from '../main/ets/model/Poi';
import { fixAt, poiAt } from './TestGeo';

function find(v: ItineraryView, id: string): UpcomingPoi | undefined {
  return v.upcoming.find((u: UpcomingPoi) => u.poi.id === id);
}

// Route-based tests (demo walk, GPS noise) run in Node in guide-lab/, because
// local unit tests cannot read rawfile. These cover the same rules on synthetic walks.
export default function itineraryTest() {
  describe('itinerary', () => {
    it('sidesPassingMissing', 0, () => {
      const it2 = new Itinerary([poiAt('right', 100, 30), poiAt('left', 150, -30), poiAt('far-side', 120, 90),
        poiAt('visited', 50, 10)]);
      const m = new MotionTracker();
      let v: ItineraryView = it2.update(m.snapshot());
      for (let k = 0; k <= 20; k++) {
        v = it2.update(m.update(fixAt(k * 4, 0, k * 3)));
      }
      const right = find(v, 'right');
      const left = find(v, 'left');
      expect(right !== undefined && right.side === Side.RIGHT).assertTrue();
      expect(left !== undefined && left.side === Side.LEFT).assertTrue();
      expect(right !== undefined && left !== undefined && right.alongM < left.alongM).assertTrue();
      expect(find(v, 'far-side') === undefined).assertTrue();
      expect(v.passedIds.indexOf('visited') >= 0 && v.missedIds.indexOf('visited') < 0).assertTrue();
      for (let k = 21; k <= 60; k++) {
        v = it2.update(m.update(fixAt(k * 4, 0, k * 3)));
      }
      expect(v.passedIds.join(',')).assertEqual('visited,right,far-side,left');
      expect(v.missedIds.join(',')).assertEqual('far-side');
    });

    it('noHeadingOnlyNearby', 0, () => {
      const it2 = new Itinerary([poiAt('near', 20, 0), poiAt('far', 100, 0)]);
      const v: ItineraryView = it2.update(new MotionTracker().update(fixAt(0, 0, 0)));
      expect(v.upcoming.length).assertEqual(1);
      expect(v.next !== null && v.next.poi.id === 'near' && v.next.side === Side.AHEAD).assertTrue();
    });

    it('standingStillFiniteEta', 0, () => {
      const it2 = new Itinerary([poiAt('a', 30, 0)]);
      const v: ItineraryView = it2.update(new MotionTracker().update(fixAt(0, 0, 0)));
      expect(v.next !== null && Math.abs(v.next.etaS - 30 / 0.8) < 1).assertTrue();
    });

    it('switchesOnlyWhen15sSooner', 0, () => {
      const m = new MotionTracker();
      for (let k = 0; k <= 8; k++) {
        m.update(fixAt(k * 4, 0, k * 3));
      }
      const pois: Poi[] = [poiAt('A', 132, 0)];
      const it2 = new Itinerary(pois);
      expect(it2.update(m.snapshot()).next?.poi.id).assertEqual('A');
      pois.push(poiAt('B', 122, 5));
      expect(it2.update(m.snapshot()).next?.poi.id).assertEqual('A');
      pois.push(poiAt('C', 62, 5));
      expect(it2.update(m.snapshot()).next?.poi.id).assertEqual('C');
    });
  });
}
