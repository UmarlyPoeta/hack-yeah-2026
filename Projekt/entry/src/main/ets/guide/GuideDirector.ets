import { GeoFix } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { Interest, Segment } from '../model/Segment';
import { Itinerary, ItineraryView } from './Itinerary';
import { MotionSnapshot, MotionTracker } from './MotionTracker';
import { GuideAction, GuideProgress, NarrationPlanner, PlannerState } from './NarrationPlanner';

// The guide engine behind one interface: events in, actions out. The view model feeds it
// location fixes, a clock tick, AI segments and player callbacks, and executes the returned actions.
// No timers, no I/O, no ArkUI: a whole walk can be replayed in a test. docs/ARCHITECTURE.md §2.

export enum GuideEventKind {
  FIX = 'FIX',                                   // new location fix
  TICK = 'TICK',                                 // time passes without a fix (call ~1 per second)
  SEGMENT_READY = 'SEGMENT_READY',               // SegmentService answered a REQUEST_SEGMENT
  PLAYBACK_FINISHED = 'PLAYBACK_FINISHED',       // the player finished (or the user skipped) a segment
  DEEP_DIVE_ACCEPTED = 'DEEP_DIVE_ACCEPTED'      // user tapped "Opowiedz więcej"
}

export interface GuideEvent {
  kind: GuideEventKind;
  t: number;                  // ms, same clock as GeoFix.t
  fix: GeoFix | null;
  segment: Segment | null;
  id: string | null;          // segment id (PLAYBACK_FINISHED) or poi id (DEEP_DIVE_ACCEPTED)
}

export class GuideEvents {
  static fix(f: GeoFix): GuideEvent {
    return GuideEvents.make(GuideEventKind.FIX, f.t, f, null, null);
  }
  static tick(t: number): GuideEvent {
    return GuideEvents.make(GuideEventKind.TICK, t, null, null, null);
  }
  static segmentReady(segment: Segment, t: number): GuideEvent {
    return GuideEvents.make(GuideEventKind.SEGMENT_READY, t, null, segment, null);
  }
  static playbackFinished(segmentId: string, t: number): GuideEvent {
    return GuideEvents.make(GuideEventKind.PLAYBACK_FINISHED, t, null, null, segmentId);
  }
  static deepDiveAccepted(poiId: string, t: number): GuideEvent {
    return GuideEvents.make(GuideEventKind.DEEP_DIVE_ACCEPTED, t, null, null, poiId);
  }
  private static make(kind: GuideEventKind, t: number, fix: GeoFix | null, segment: Segment | null,
    id: string | null): GuideEvent {
    const e: GuideEvent = { kind: kind, t: t, fix: fix, segment: segment, id: id };
    return e;
  }
}

export class GuideDirector {
  private tracker: MotionTracker = new MotionTracker();
  private itinerary: Itinerary;
  private planner: NarrationPlanner;
  private view: ItineraryView;
  private lastT: number = 0;

  constructor(pois: Poi[], interests: Interest[], voice: boolean) {
    this.itinerary = new Itinerary(pois);
    this.planner = new NarrationPlanner(pois, interests, voice);
    this.view = this.itinerary.update(this.tracker.snapshot());
  }

  step(e: GuideEvent): GuideAction[] {
    // events must not go back in time; a late one is handled as if it came now
    const t = Math.max(e.t, this.lastT);
    this.lastT = t;
    if (e.kind === GuideEventKind.FIX && e.fix !== null) {
      this.view = this.itinerary.update(this.tracker.update(e.fix));
      return this.planner.update(t, this.tracker.snapshot(), this.view);
    }
    if (e.kind === GuideEventKind.SEGMENT_READY && e.segment !== null) {
      this.planner.segmentReady(e.segment);
    } else if (e.kind === GuideEventKind.PLAYBACK_FINISHED && e.id !== null) {
      this.planner.playbackFinished(e.id, t);
    } else if (e.kind === GuideEventKind.DEEP_DIVE_ACCEPTED && e.id !== null) {
      const accepted = this.planner.acceptDeepDive(e.id, t);
      return accepted.concat(this.planner.update(t, this.tracker.snapshot(), this.view));
    }
    return this.planner.update(t, this.tracker.snapshot(), this.view);
  }

  // Commands from the user or the other device. Each returns the actions to execute now.
  skip(t: number): GuideAction[] {
    const now = this.advance(t);
    this.planner.skip(now);
    return this.planner.update(now, this.tracker.snapshot(), this.view);
  }

  replay(t: number): GuideAction[] {
    return this.planner.replay(this.advance(t));
  }

  setMuted(muted: boolean, t: number): GuideAction[] {
    const now = this.advance(t);
    this.planner.setMuted(muted);
    return this.planner.update(now, this.tracker.snapshot(), this.view);
  }

  isMuted(): boolean {
    return this.planner.isMuted();
  }

  exportProgress(): GuideProgress {
    return this.planner.exportProgress();
  }

  importProgress(p: GuideProgress): void {
    this.planner.importProgress(p);
  }

  private advance(t: number): number {
    this.lastT = Math.max(t, this.lastT);
    return this.lastT;
  }

  motion(): MotionSnapshot {
    return this.tracker.snapshot();
  }

  itineraryView(): ItineraryView {
    return this.view;
  }

  plannerState(): PlannerState {
    return this.planner.state();
  }
}
