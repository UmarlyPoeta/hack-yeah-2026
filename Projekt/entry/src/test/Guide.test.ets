import { describe, it, expect } from '@ohos/hypium';
import { PoiRole, Poi } from '../main/ets/model/Poi';
import { Segment, SegmentKind } from '../main/ets/model/Segment';
import { buildStops, Stop } from '../main/ets/guide/Stops';
import { GuideDirector } from '../main/ets/guide/GuideDirector';
import { GuideAction, GuideActionKind } from '../main/ets/guide/NarrationPlanner';
import { playedSegments, poiAt, runWalk, standAt, walkNorth } from './TestGeo';

function kinds(segments: Segment[]): string {
  return segments.map((s: Segment) => s.kind).join(',');
}

function countKind(segments: Segment[], kind: SegmentKind): number {
  return segments.filter((s: Segment) => s.kind === kind).length;
}

export default function guideTest() {
  describe('guide', () => {
    it('stopsClusterAndSkipAreas', 0, () => {
      const stops: Stop[] = buildStops([poiAt('church', 0, 0, 0.9), poiAt('parish', 5, 5, 0.1), poiAt('far', 100, 0, 0.5),
        poiAt('square', 0, 10, 0.95, PoiRole.AREA)]);
      expect(stops.length).assertEqual(2);
      expect(stops[0].members.map((p: Poi) => p.id).join('+')).assertEqual('church+parish');
    });

    it('closeSightsAreOneStory', 0, () => {
      const pois: Poi[] = [poiAt('Brama', 60, 5, 0.8), poiAt('Baszta', 75, 5, 0.5), poiAt('Kościół', 300, 5, 0.8)];
      const p: Segment[] = playedSegments(runWalk(new GuideDirector(pois, [], true), walkNorth(0, 120, 0)));
      expect(p[0].kind).assertEqual(SegmentKind.WELCOME);
      const arrivals: Segment[] = p.filter((s: Segment) => s.kind === SegmentKind.ARRIVAL);
      expect(arrivals.length).assertEqual(1);
      expect(arrivals[0].text.indexOf('Obok: Baszta') >= 0).assertTrue();
    });

    it('standingOnBorderOneArrival', 0, () => {
      const fixes = walkNorth(0, 66, 0).concat(standAt(66, 60, 10), standAt(64, 70, 5), standAt(52, 75, 5));
      const p: Segment[] = playedSegments(runWalk(new GuideDirector([poiAt('Pomnik', 100, 0, 0.8)], [], true), fixes));
      expect(countKind(p, SegmentKind.ARRIVAL)).assertEqual(1);
    });

    it('stoppingOffersDeepDive', 0, () => {
      const d = new GuideDirector([poiAt('Sukiennice', 60, 10, 0.9)], [], true);
      runWalk(d, walkNorth(0, 62, 0));
      const standing: GuideAction[] = runWalk(d, standAt(62, 48, 50));
      expect(standing.some((a: GuideAction) => a.kind === GuideActionKind.OFFER_DEEP_DIVE)).assertTrue();
    });

    it('walkingNeverOffers', 0, () => {
      const a: GuideAction[] = runWalk(new GuideDirector([poiAt('Pomnik', 60, 10, 0.9)], [], true), walkNorth(0, 200, 0));
      expect(a.some((x: GuideAction) => x.kind === GuideActionKind.OFFER_DEEP_DIVE)).assertFalse();
    });

    it('noPlacesOnlyWelcome', 0, () => {
      const p: Segment[] = playedSegments(runWalk(new GuideDirector([], [], true), walkNorth(0, 100, 0)));
      expect(kinds(p)).assertEqual('WELCOME');
    });
  });
}
