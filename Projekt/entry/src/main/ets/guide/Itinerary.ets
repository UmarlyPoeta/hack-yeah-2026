import { Poi } from '../model/Poi';
import { distanceM, relativePosition, RelativePosition } from './geo';
import { MotionSnapshot } from './MotionTracker';

// Works out which places are ahead of the walker, in what order, how soon they are reached
// and on which side; and which were passed or missed. Algorithm: docs/ARCHITECTURE.md §2.2.

export enum Side {
  LEFT = 'LEFT',
  RIGHT = 'RIGHT',
  AHEAD = 'AHEAD'   // roughly straight ahead, or heading unknown
}

export interface UpcomingPoi {
  poi: Poi;
  distanceM: number;
  alongM: number;     // metres left to the place along the walking direction
  crossM: number;     // > 0 right, < 0 left
  side: Side;
  etaS: number;       // seconds until the place is reached at the current pace
}

export interface ItineraryView {
  next: UpcomingPoi | null;    // the place the guide is heading for; changes only on purpose
  upcoming: UpcomingPoi[];     // everything ahead, sorted by alongM
  passedIds: string[];         // passed in this walk, in the order they were (finally) passed
  missedIds: string[];         // passed without ever coming within VISIT_RADIUS_M
}

export const LOOKAHEAD_RADIUS_M: number = 250;
export const CORRIDOR_HALF_WIDTH_M: number = 60;   // max |cross| to count as "ahead"
export const NEARBY_M: number = 40;                // this close counts as ahead whatever the heading
export const PASSED_BEHIND_M: number = 20;         // along below -20 m means passed
export const VISIT_RADIUS_M: number = 35;          // came this close = visited, not missed
export const MIN_ETA_SPEED_MPS: number = 0.8;      // so standing still does not give infinite ETA
export const NEXT_SWITCH_GAIN_S: number = 15;      // another place must be this much sooner to take over
const SIDE_DEADBAND_M: number = 5;

export class Itinerary {
  private pois: Poi[];
  private minDistance: Map<string, number> = new Map<string, number>();
  private passed: Set<string> = new Set<string>();
  private passedOrder: string[] = [];
  private nextId: string | null = null;

  constructor(pois: Poi[]) {
    this.pois = pois;
  }

  update(motion: MotionSnapshot): ItineraryView {
    const upcoming: UpcomingPoi[] = [];
    const inRange: Map<string, UpcomingPoi> = new Map<string, UpcomingPoi>();
    if (motion.position !== null) {
      for (const poi of this.pois) {
        const item = this.locate(poi, motion);
        if (item === null) {
          continue;
        }
        inRange.set(poi.id, item);
        if (this.passed.has(poi.id)) {
          if (!this.isBackInReach(item, motion.headingDeg !== null)) {
            continue;
          }
          // after a turn the route can lead back past a place that was briefly behind us
          this.passed.delete(poi.id);
          this.passedOrder.splice(this.passedOrder.indexOf(poi.id), 1);
        }
        if (motion.headingDeg !== null && item.alongM < -PASSED_BEHIND_M) {
          this.passed.add(poi.id);
          this.passedOrder.push(poi.id);
          continue;
        }
        if (this.isAhead(item, motion.headingDeg !== null)) {
          upcoming.push(item);
        }
      }
    }
    upcoming.sort((a: UpcomingPoi, b: UpcomingPoi) => a.alongM - b.alongM);
    const view: ItineraryView = {
      next: this.chooseNext(upcoming, inRange),
      upcoming: upcoming,
      passedIds: this.passedOrder.slice(),
      missedIds: this.missed()
    };
    return view;
  }

  // Distance, along/cross and ETA for one place, or null when it is outside the lookahead radius.
  private locate(poi: Poi, motion: MotionSnapshot): UpcomingPoi | null {
    const position = motion.position;
    if (position === null) {
      return null;
    }
    const d = distanceM(position, poi);
    const prevMin = this.minDistance.get(poi.id);
    if (prevMin === undefined || d < prevMin) {
      this.minDistance.set(poi.id, d);
    }
    if (d > LOOKAHEAD_RADIUS_M) {
      return null;
    }
    let alongM = d;   // without a heading we only know the distance
    let crossM = 0;
    if (motion.headingDeg !== null) {
      const rel: RelativePosition = relativePosition(position, motion.headingDeg, poi);
      alongM = rel.alongM;
      crossM = rel.crossM;
    }
    const speed = Math.max(motion.speedMps, MIN_ETA_SPEED_MPS);
    const item: UpcomingPoi = {
      poi: poi,
      distanceM: d,
      alongM: alongM,
      crossM: crossM,
      side: crossM > SIDE_DEADBAND_M ? Side.RIGHT : (crossM < -SIDE_DEADBAND_M ? Side.LEFT : Side.AHEAD),
      etaS: Math.max(alongM, 0) / speed
    };
    return item;
  }

  private isAhead(item: UpcomingPoi, headingKnown: boolean): boolean {
    if (item.distanceM < NEARBY_M) {
      return true;
    }
    return headingKnown && item.alongM > 0 && Math.abs(item.crossM) <= CORRIDOR_HALF_WIDTH_M;
  }

  // A passed place counts again only when we are right next to it and it is ahead again.
  // along >= 0 here vs < -20 m for passing: the 20 m gap stops GPS noise toggling it.
  private isBackInReach(item: UpcomingPoi, headingKnown: boolean): boolean {
    return headingKnown && item.distanceM < NEARBY_M && item.alongM >= 0;
  }

  // Keeps the current target until it is passed or left behind the radius, until another place
  // would be reached NEXT_SWITCH_GAIN_S sooner, or until it leaves the corridor while something
  // nearer is ahead. Going back to an old target needs the full gain, so it cannot flicker.
  private chooseNext(upcoming: UpcomingPoi[], inRange: Map<string, UpcomingPoi>): UpcomingPoi | null {
    const best: UpcomingPoi | null = upcoming.length > 0 ? upcoming[0] : null;
    const current: UpcomingPoi | undefined = this.nextId !== null ? inRange.get(this.nextId) : undefined;
    let chosen: UpcomingPoi | null = best;
    if (current !== undefined && !this.passed.has(current.poi.id)) {
      chosen = current;
      const currentAhead = upcoming.indexOf(current) >= 0;
      if (best !== null && best.etaS < current.etaS - NEXT_SWITCH_GAIN_S) {
        chosen = best;
      } else if (best !== null && !currentAhead && best.etaS < current.etaS) {
        // the target drifted out of the corridor (e.g. a long wall beside the street):
        // do not cling to it while something nearer is right ahead
        chosen = best;
      }
    }
    this.nextId = chosen !== null ? chosen.poi.id : null;
    return chosen;
  }

  private missed(): string[] {
    const result: string[] = [];
    for (const id of this.passedOrder) {
      const minD = this.minDistance.get(id);
      if (minD === undefined || minD >= VISIT_RADIUS_M) {
        result.push(id);
      }
    }
    return result;
  }
}
