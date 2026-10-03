import { GeoPoint } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { Interest, Segment, SegmentKind } from '../model/Segment';
import { relativePosition } from './geo';
import { ItineraryView, Side, UpcomingPoi } from './Itinerary';
import { MotionSnapshot, MotionState } from './MotionTracker';
import { buildStops, distanceToStop, localThreshold, MIN_IMPORTANCE, Stop } from './Stops';
import {
  approachText, arrivalText, bridgeText, deepDiveText, estimateDurationMs, missedText, segmentKey,
  templateSegment, welcomeText, WORDS_PER_SECOND
} from './Templates';

// Decides what the guide says, when, and how long. One segment at a time; nothing is ever cut off.
// Pure logic: everything comes in through update()/events with an explicit time, everything goes out
// as GuideAction data for the view model to execute. Algorithm: docs/ARCHITECTURE.md §2.3.

export enum GuideActionKind {
  REQUEST_SEGMENT = 'REQUEST_SEGMENT',     // ask SegmentService for an AI segment, answer before deadlineT
  PLAY_SEGMENT = 'PLAY_SEGMENT',           // show and speak this segment now
  OFFER_DEEP_DIVE = 'OFFER_DEEP_DIVE',     // show "Opowiedz więcej o ..." for poiId
  WITHDRAW_DEEP_DIVE = 'WITHDRAW_DEEP_DIVE'
}

export interface SegmentRequest {          // body of POST /v1/segment (docs/CONTRACTS.md)
  kind: SegmentKind;
  poiId: string;
  fromPoiId: string | null;
  interests: Interest[];
  maxWords: number;
  voice: boolean;
}

export interface GuideAction {
  kind: GuideActionKind;
  t: number;
  segment: Segment | null;          // PLAY_SEGMENT
  request: SegmentRequest | null;   // REQUEST_SEGMENT
  deadlineT: number;                // REQUEST_SEGMENT: after this the template is used anyway
  poiId: string | null;             // OFFER_/WITHDRAW_DEEP_DIVE
}

// Tunables (seconds, metres, words)
export const ARRIVE_M: number = 35;
export const LEAVE_M: number = 50;
export const APPROACH_MAX_ETA_S: number = 30;
export const APPROACH_MIN_ETA_S: number = 8;
export const BRIDGE_MIN_ETA_S: number = 25;
export const FILLER_MIN_GAP_S: number = 90;     // a minor stop is narrated only if the next main one is this far
export const FILLER_QUIET_MS: number = 30000;   // ...and the guide has been quiet this long since the last stop
export const BRIDGE_WINDOW_MS: number = 30000;  // a BRIDGE only right after the stop's story, never much later
export const LATE_ARRIVAL_M: number = 60;       // a main stop passed this close still gets its story
export const MISSED_MAX_M: number = 120;        // "we passed X" only for places that were in sight
export const MISSED_INTERVAL_MS: number = 60000; // at most one "we passed X" per minute
export const DEEP_DIVE_AFTER_MS: number = 8000;
export const DEEP_DIVE_WAIT_MS: number = 8000;  // how long a deep dive waits for the AI text before the template
export const DEEP_DIVE_WORDS: number = 300;
export const ARRIVAL_MIN_WORDS: number = 40;
export const ARRIVAL_MAX_WORDS: number = 120;
export const BRIDGE_MIN_WORDS: number = 20;
export const BRIDGE_MAX_WORDS: number = 70;
export const MISSED_TTL_MS: number = 60000;
export const ARRIVAL_DROP_M: number = 80;       // a queued ARRIVAL is dropped once we are this far away

const PRIORITY: Map<SegmentKind, number> = new Map<SegmentKind, number>([
  [SegmentKind.WELCOME, 5], [SegmentKind.ARRIVAL, 4], [SegmentKind.DEEP_DIVE, 4], [SegmentKind.APPROACH, 3],
  [SegmentKind.BRIDGE, 2], [SegmentKind.MISSED, 1]
]);

interface Pending {
  kind: SegmentKind;
  stop: Stop | null;            // null only for WELCOME without any stop ahead
  fromStop: Stop | null;        // BRIDGE
  maxWords: number;
  enqueuedT: number;
  waitUntilT: number;           // play only with an AI segment until then (deep dive)
  side: Side;
  distanceM: number;            // APPROACH / WELCOME wording
}

// What the planner currently thinks; read by the view model for the screen.
export interface PlannerState {
  nextStop: Stop | null;
  nextEtaS: number;
  speaking: Segment | null;
  speakingUntilT: number;
  offerStopId: string | null;
  threshold: number;
  spokenStopIds: string[];      // stops that got an ARRIVAL, in order
  upcomingMain: Stop[];         // main stops ahead not told yet, soonest first ("DALEJ NA TRASIE")
}

interface StopAhead {
  stop: Stop;
  item: UpcomingPoi;            // the member that is soonest
  arriveS: number;              // seconds until its ARRIVAL starts (we start talking at ARRIVE_M, not at the door)
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}

export class NarrationPlanner {
  private stops: Stop[];
  private stopOfPoi: Map<string, Stop> = new Map<string, Stop>();
  private interests: Interest[];
  private voice: boolean;
  private welcomed: boolean = false;
  private arrived: Set<string> = new Set<string>();      // ARRIVAL queued or played
  private announced: Set<string> = new Set<string>();    // APPROACH queued
  private bridged: Set<string> = new Set<string>();      // BRIDGE decided (queued or skipped) after this stop
  private missedSaid: Set<string> = new Set<string>();
  private minDistance: Map<string, number> = new Map<string, number>();   // closest we came to each stop
  private lastMissedT: number = -MISSED_INTERVAL_MS;
  private offered: Set<string> = new Set<string>();
  private requested: Set<string> = new Set<string>();
  private ready: Map<string, Segment> = new Map<string, Segment>();
  private queue: Pending[] = [];
  private speaking: Segment | null = null;
  private speakingUntilT: number = 0;
  private lastArrival: Stop | null = null;
  private lastArrivalEndT: number = 0;
  private offerStop: Stop | null = null;
  private nextStop: Stop | null = null;
  private nextEtaS: number = 0;     // seconds until the next main stop's ARRIVAL starts
  private afterGapS: number = 0;    // seconds from that ARRIVAL to the one after it
  private threshold: number = 0;
  private spokenOrder: string[] = [];
  private upcomingMain: Stop[] = [];

  constructor(pois: Poi[], interests: Interest[], voice: boolean) {
    this.stops = buildStops(pois);
    for (const s of this.stops) {
      for (const m of s.members) {
        this.stopOfPoi.set(m.id, s);
      }
    }
    this.interests = interests;
    this.voice = voice;
  }

  state(): PlannerState {
    const s: PlannerState = {
      nextStop: this.nextStop,
      nextEtaS: this.nextEtaS,
      speaking: this.speaking,
      speakingUntilT: this.speakingUntilT,
      offerStopId: this.offerStop !== null ? this.offerStop.id : null,
      threshold: this.threshold,
      spokenStopIds: this.spokenOrder.slice(),
      upcomingMain: this.upcomingMain.slice()
    };
    return s;
  }

  stopList(): Stop[] {
    return this.stops;
  }

  // An AI segment arrived from SegmentService. It is used if its turn has not come yet.
  segmentReady(segment: Segment): void {
    this.ready.set(segmentKey(segment.kind, segment.poiId, segment.fromPoiId), segment);
  }

  // The player finished (or the user skipped) a segment: the narrator is free from now on.
  playbackFinished(segmentId: string, t: number): void {
    if (this.speaking !== null && this.speaking.id === segmentId && t < this.speakingUntilT) {
      if (this.speaking.kind === SegmentKind.ARRIVAL) {
        this.lastArrivalEndT = t;
      }
      this.speakingUntilT = t;
    }
  }

  acceptDeepDive(stopId: string, t: number): GuideAction[] {
    const actions: GuideAction[] = [];
    const stop = this.stopOfPoi.get(stopId);
    if (stop === undefined || this.offerStop === null || this.offerStop.id !== stop.id) {
      return actions;
    }
    this.offerStop = null;
    this.enqueue(SegmentKind.DEEP_DIVE, stop, null, DEEP_DIVE_WORDS, t, Side.AHEAD, 0);
    this.queue[this.queue.length - 1].waitUntilT = t + DEEP_DIVE_WAIT_MS;
    this.request(actions, SegmentKind.DEEP_DIVE, stop, null, DEEP_DIVE_WORDS, t + DEEP_DIVE_WAIT_MS, t);
    return actions;
  }

  update(t: number, motion: MotionSnapshot, view: ItineraryView): GuideAction[] {
    const actions: GuideAction[] = [];
    const position = motion.position;
    if (position === null) {
      return actions;
    }
    this.threshold = localThreshold(position, this.stops);
    const ahead = this.stopsAhead(view);
    this.updateNext(ahead, t, actions);

    if (!this.welcomed) {
      this.welcomed = true;
      const first = this.nextStop;
      this.enqueue(SegmentKind.WELCOME, first, null, 0, t, Side.AHEAD, first !== null ? this.etaToDistance(ahead, first) : 0);
    }
    this.checkArrivals(position, t);
    this.checkApproach(ahead, t);
    this.checkBridge(t, motion);
    this.checkMissed(view, motion, t);
    this.dropExpired(position, t);
    this.checkOffer(position, t, motion, actions);
    this.playNext(t, actions);
    return actions;
  }

  private isMain(stop: Stop): boolean {
    return stop.importance >= this.threshold;
  }

  // Upcoming places collapsed into stops, soonest first.
  private stopsAhead(view: ItineraryView): StopAhead[] {
    const seen = new Set<string>();
    const result: StopAhead[] = [];
    for (const item of view.upcoming) {           // already sorted by alongM
      const stop = this.stopOfPoi.get(item.poi.id);
      if (stop === undefined || seen.has(stop.id)) {
        continue;
      }
      seen.add(stop.id);
      const arriveS = item.alongM > 0 ? item.etaS * Math.max(0, item.alongM - ARRIVE_M) / item.alongM : 0;
      const sa: StopAhead = { stop: stop, item: item, arriveS: arriveS };
      result.push(sa);
    }
    return result;
  }

  private etaToDistance(ahead: StopAhead[], stop: Stop): number {
    for (const a of ahead) {
      if (a.stop.id === stop.id) {
        return a.item.distanceM;
      }
    }
    return 0;
  }

  // Next main stop not yet narrated; prefetch its ARRIVAL text when it changes.
  private updateNext(ahead: StopAhead[], t: number, actions: GuideAction[]): void {
    let next: StopAhead | null = null;
    let after: StopAhead | null = null;
    this.upcomingMain = [];
    for (const a of ahead) {
      if (!this.isMain(a.stop) || this.arrived.has(a.stop.id)) {
        continue;
      }
      this.upcomingMain.push(a.stop);
      if (next === null) {
        next = a;
      } else if (after === null) {
        after = a;
      }
    }
    const changed = (next === null) !== (this.nextStop === null)
      || (next !== null && this.nextStop !== null && next.stop.id !== this.nextStop.id);
    this.nextStop = next !== null ? next.stop : null;
    this.nextEtaS = next !== null ? next.arriveS : 0;
    this.afterGapS = next !== null && after !== null ? after.arriveS - next.arriveS : ARRIVAL_MAX_WORDS;
    if (changed && next !== null) {
      this.request(actions, SegmentKind.ARRIVAL, next.stop, null, this.arrivalBudget(this.afterGapS), t + next.arriveS * 1000, t);
    }
  }

  // ARRIVAL length fits the walk to the next stop: clamp(gap × 2.5 words/s × 0.7, 40, 120).
  private arrivalBudget(gapS: number): number {
    return Math.round(clamp(gapS * WORDS_PER_SECOND * 0.7, ARRIVAL_MIN_WORDS, ARRIVAL_MAX_WORDS));
  }

  private checkArrivals(position: GeoPoint, t: number): void {
    for (const stop of this.stops) {
      const d = distanceToStop(position, stop);
      const prev = this.minDistance.get(stop.id);
      if (prev === undefined || d < prev) {
        this.minDistance.set(stop.id, d);
      }
      if (this.arrived.has(stop.id) || d >= ARRIVE_M) {
        continue;
      }
      // a minor stop only when the narrator has had nothing to say for a while and will not soon
      const nextGapS = this.nextStop !== null && this.nextStop.id !== stop.id ? this.nextEtaS : FILLER_MIN_GAP_S;
      const quiet = !this.isSpeaking(t) && this.queue.length === 0 && t - this.lastArrivalEndT >= FILLER_QUIET_MS;
      if (!this.isMain(stop) && (stop.importance < MIN_IMPORTANCE || !quiet || nextGapS < FILLER_MIN_GAP_S)) {
        continue;
      }
      this.arrived.add(stop.id);
      // time until the following main stop starts: that is how long this story may last
      const gapS = this.nextStop === null ? ARRIVAL_MAX_WORDS
        : (this.nextStop.id === stop.id ? this.afterGapS : this.nextEtaS);
      // if this stop was announced, drop the now pointless APPROACH
      this.queue = this.queue.filter((p: Pending) => !(p.kind === SegmentKind.APPROACH && p.stop !== null && p.stop.id === stop.id));
      this.enqueue(SegmentKind.ARRIVAL, stop, null, this.arrivalBudget(gapS), t, Side.AHEAD, 0);
    }
  }

  private checkApproach(ahead: StopAhead[], t: number): void {
    const next = this.nextStop;
    if (next === null || this.announced.has(next.id) || this.isSpeaking(t) || this.queue.length > 0) {
      return;
    }
    for (const a of ahead) {
      if (a.stop.id !== next.id) {
        continue;
      }
      if (a.arriveS <= APPROACH_MAX_ETA_S && a.arriveS >= APPROACH_MIN_ETA_S) {
        this.announced.add(next.id);
        this.enqueue(SegmentKind.APPROACH, next, null, 0, t, a.item.side, a.item.distanceM);
      }
      return;
    }
  }

  // After an ARRIVAL, once the user walks on, link it with the next main stop if there is time.
  private checkBridge(t: number, motion: MotionSnapshot): void {
    const from = this.lastArrival;
    if (from === null || this.bridged.has(from.id) || this.isSpeaking(t)) {
      return;
    }
    if (!this.isMain(from) || t - this.lastArrivalEndT > BRIDGE_WINDOW_MS) {
      this.bridged.add(from.id);   // minor stop, or the moment has passed: the APPROACH will do
      return;
    }
    const next = this.nextStop;
    if (next === null || next.id === from.id) {
      return;
    }
    if (this.nextEtaS < BRIDGE_MIN_ETA_S) {
      this.bridged.add(from.id);   // stops too close together: the APPROACH will do ("Tuż obok")
      return;
    }
    if (motion.state !== MotionState.MOVING) {
      return;
    }
    this.bridged.add(from.id);
    const words = Math.round(clamp(this.nextEtaS * WORDS_PER_SECOND * 0.6, BRIDGE_MIN_WORDS, BRIDGE_MAX_WORDS));
    this.enqueue(SegmentKind.BRIDGE, next, from, words, t, Side.AHEAD, 0);
  }

  private checkMissed(view: ItineraryView, motion: MotionSnapshot, t: number): void {
    const position = motion.position;
    if (position === null) {
      return;
    }
    for (const id of view.missedIds) {
      const stop = this.stopOfPoi.get(id);
      if (stop === undefined || stop.anchor.id !== id || !this.isMain(stop) || this.arrived.has(stop.id)
        || this.missedSaid.has(stop.id)) {
        continue;
      }
      this.missedSaid.add(stop.id);
      const closest = this.minDistance.get(stop.id);
      if (closest === undefined || closest >= MISSED_MAX_M) {
        continue;                  // never really in sight: say nothing
      }
      const promised = this.announced.has(stop.id);
      if ((closest < LATE_ARRIVAL_M || promised) && distanceToStop(position, stop) < ARRIVAL_DROP_M) {
        // passed close by (a tower in the middle of a square), or we announced it: tell its story late
        // rather than "we missed it"
        this.arrived.add(stop.id);
        this.queue = this.queue.filter((p: Pending) => !(p.kind === SegmentKind.APPROACH && p.stop !== null && p.stop.id === stop.id));
        this.enqueue(SegmentKind.ARRIVAL, stop, null, ARRIVAL_MIN_WORDS, t, Side.AHEAD, 0);
        continue;
      }
      if (t - this.lastMissedT < MISSED_INTERVAL_MS) {
        continue;
      }
      this.lastMissedT = t;
      let side = Side.AHEAD;
      if (motion.headingDeg !== null) {
        const cross = relativePosition(position, motion.headingDeg, stop.anchor).crossM;
        side = cross > 5 ? Side.RIGHT : (cross < -5 ? Side.LEFT : Side.AHEAD);
      }
      this.enqueue(SegmentKind.MISSED, stop, null, 0, t, side, 0);
    }
  }

  private dropExpired(position: GeoPoint, t: number): void {
    this.queue = this.queue.filter((p: Pending) => {
      if (p.stop === null) {
        return true;
      }
      if (p.kind === SegmentKind.APPROACH) {
        return distanceToStop(position, p.stop) >= ARRIVE_M && !this.arrived.has(p.stop.id);
      }
      if (p.kind === SegmentKind.ARRIVAL || p.kind === SegmentKind.DEEP_DIVE) {
        return distanceToStop(position, p.stop) < ARRIVAL_DROP_M;
      }
      if (p.kind === SegmentKind.BRIDGE) {
        return !this.arrived.has(p.stop.id);
      }
      if (p.kind === SegmentKind.MISSED) {
        return t - p.enqueuedT < MISSED_TTL_MS;
      }
      return true;
    });
  }

  // Standing still at the stop we just heard about, narrator quiet: offer more.
  private checkOffer(position: GeoPoint, t: number, motion: MotionSnapshot, actions: GuideAction[]): void {
    const offer = this.offerStop;
    if (offer !== null) {
      if (motion.state === MotionState.MOVING || distanceToStop(position, offer) > LEAVE_M) {
        this.offerStop = null;
        actions.push(this.action(GuideActionKind.WITHDRAW_DEEP_DIVE, t, null, null, 0, offer.id));
      }
      return;
    }
    const last = this.lastArrival;
    if (last === null || this.offered.has(last.id) || this.isSpeaking(t) || this.queue.length > 0) {
      return;
    }
    if (motion.state === MotionState.STOPPED && t - this.lastArrivalEndT >= DEEP_DIVE_AFTER_MS
      && distanceToStop(position, last) <= LEAVE_M) {
      this.offered.add(last.id);
      this.offerStop = last;
      actions.push(this.action(GuideActionKind.OFFER_DEEP_DIVE, t, null, null, 0, last.id));
    }
  }

  private isSpeaking(t: number): boolean {
    return t < this.speakingUntilT;
  }

  private playNext(t: number, actions: GuideAction[]): void {
    if (this.isSpeaking(t)) {
      return;
    }
    this.speaking = null;
    let best = -1;
    for (let i = 0; i < this.queue.length; i++) {
      const p = this.queue[i];
      if (p.waitUntilT > t && !this.ready.has(this.keyOf(p))) {
        continue;
      }
      if (best < 0 || this.priorityOf(p) > this.priorityOf(this.queue[best])) {
        best = i;                    // ties keep the earlier one
      }
    }
    if (best < 0) {
      return;
    }
    const p = this.queue[best];
    this.queue.splice(best, 1);
    const segment = this.segmentFor(p);
    const duration = segment.durationMs !== null ? segment.durationMs : estimateDurationMs(segment.text);
    this.speaking = segment;
    this.speakingUntilT = t + duration;
    actions.push(this.action(GuideActionKind.PLAY_SEGMENT, t, segment, null, 0, null));
    if (p.kind === SegmentKind.ARRIVAL && p.stop !== null) {
      this.lastArrival = p.stop;
      this.lastArrivalEndT = this.speakingUntilT;
      this.spokenOrder.push(p.stop.id);
      // prefetch the link to the next stop while this one is being told
      if (this.nextStop !== null && this.nextStop.id !== p.stop.id && this.nextEtaS >= BRIDGE_MIN_ETA_S) {
        const words = Math.round(clamp(this.nextEtaS * WORDS_PER_SECOND * 0.6, BRIDGE_MIN_WORDS, BRIDGE_MAX_WORDS));
        this.request(actions, SegmentKind.BRIDGE, this.nextStop, p.stop, words, this.speakingUntilT, t);
      }
    }
  }

  private priorityOf(p: Pending): number {
    const v = PRIORITY.get(p.kind);
    return v !== undefined ? v : 0;
  }

  private keyOf(p: Pending): string {
    const id = p.stop !== null ? p.stop.id : '';
    return segmentKey(p.kind, id, p.fromStop !== null ? p.fromStop.id : null);
  }

  // The AI segment if it arrived in time, otherwise the template.
  private segmentFor(p: Pending): Segment {
    const ai = this.ready.get(this.keyOf(p));
    if (ai !== undefined && ai.text.trim().length > 0) {
      return ai;
    }
    const stop = p.stop;
    if (stop === null) {
      return templateSegment(SegmentKind.WELCOME, null, null, welcomeText(null, 0));
    }
    let text = '';
    if (p.kind === SegmentKind.WELCOME) {
      text = welcomeText(stop.anchor, p.distanceM);
    } else if (p.kind === SegmentKind.APPROACH) {
      text = approachText(stop.anchor, p.distanceM, p.side);
    } else if (p.kind === SegmentKind.ARRIVAL) {
      text = arrivalText(stop.anchor, p.maxWords, stop.members.slice(1));
    } else if (p.kind === SegmentKind.BRIDGE && p.fromStop !== null) {
      text = bridgeText(p.fromStop.anchor, stop.anchor);
    } else if (p.kind === SegmentKind.DEEP_DIVE) {
      text = deepDiveText(stop.anchor, p.maxWords);
    } else {
      text = missedText(stop.anchor, p.side);
    }
    return templateSegment(p.kind, stop.anchor, p.fromStop !== null ? p.fromStop.anchor.id : null, text);
  }

  private enqueue(kind: SegmentKind, stop: Stop | null, fromStop: Stop | null, maxWords: number, t: number,
    side: Side, distance: number): void {
    const p: Pending = {
      kind: kind, stop: stop, fromStop: fromStop, maxWords: maxWords, enqueuedT: t, waitUntilT: 0,
      side: side, distanceM: distance
    };
    this.queue.push(p);
  }

  private request(actions: GuideAction[], kind: SegmentKind, stop: Stop, fromStop: Stop | null, maxWords: number,
    deadlineT: number, t: number): void {
    const key = segmentKey(kind, stop.id, fromStop !== null ? fromStop.id : null);
    if (this.requested.has(key)) {
      return;
    }
    this.requested.add(key);
    const r: SegmentRequest = {
      kind: kind, poiId: stop.id, fromPoiId: fromStop !== null ? fromStop.id : null,
      interests: this.interests.slice(), maxWords: maxWords, voice: this.voice
    };
    actions.push(this.action(GuideActionKind.REQUEST_SEGMENT, t, null, r, deadlineT, null));
  }

  private action(kind: GuideActionKind, t: number, segment: Segment | null, request: SegmentRequest | null,
    deadlineT: number, poiId: string | null): GuideAction {
    const a: GuideAction = { kind: kind, t: t, segment: segment, request: request, deadlineT: deadlineT, poiId: poiId };
    return a;
  }
}
