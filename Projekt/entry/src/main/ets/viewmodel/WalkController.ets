import { GeoFix } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { Interest, Segment, SegmentKind, SegmentOrigin } from '../model/Segment';
import { angleDiffDeg, bearingDeg } from '../guide/geo';
import { GuideDirector, GuideEvent, GuideEvents } from '../guide/GuideDirector';
import { GuideAction, GuideActionKind, SegmentRequest } from '../guide/NarrationPlanner';
import { MotionState } from '../guide/MotionTracker';
import { distanceToStop, Stop } from '../guide/Stops';
import { displayName } from '../guide/Templates';

// Connects the guide engine to the outside world through three small ports, and keeps the
// screen state the walk page draws. No ArkUI here: WalkViewModel.ets wraps this class with
// @ObservedV2 for the UI, and tests drive it with fakes.

// Server client (P3 SegmentService behind an adapter). Resolve null on any failure: the template is used.
export interface SegmentClient {
  request(req: SegmentRequest, deadlineT: number): Promise<Segment | null>;
}

// The narrator (P5 NarratorPlayer behind an adapter). Must call WalkController.playbackFinished when done.
export interface NarrationOutput {
  play(segment: Segment): void;
  stop(): void;
}

export interface Clock {
  now(): number;   // ms, the same clock the location fixes use
}

// Exactly the fields WalkPage draws (see its "mock until WalkViewModel" state).
export interface WalkUiState {
  currentText: string;          // what is being said now (teleprompter)
  segmentKind: string;          // WELCOME / APPROACH / ARRIVAL / ...
  poiName: string;              // place the current segment is about
  originLabel: string;          // "AI · bielik…" or "szablon": always shown, never hidden
  sourceUrl: string;            // Wikipedia link for the current segment (CC BY-SA)
  nextPoiName: string;          // next main stop, '' if none
  distanceM: number;            // to the next main stop
  etaSeconds: number;
  bearingAngle: number;         // where the next stop is relative to the walking direction, degrees, 0 = ahead
  laterStops: string[];         // main stops after the next one, up to 4
  moving: boolean;
  deepDiveOfferId: string;      // '' when no offer is shown
  deepDiveOfferName: string;
  storiesTold: number;
}

export function emptyUiState(): WalkUiState {
  const s: WalkUiState = {
    currentText: '', segmentKind: '', poiName: '', originLabel: '', sourceUrl: '', nextPoiName: '', distanceM: 0,
    etaSeconds: 0, bearingAngle: 0, laterStops: [], moving: false, deepDiveOfferId: '', deepDiveOfferName: '',
    storiesTold: 0
  };
  return s;
}

export class WalkController {
  private director: GuideDirector;
  private client: SegmentClient | null;
  private output: NarrationOutput;
  private clock: Clock;
  private poiById: Map<string, Poi> = new Map<string, Poi>();
  private ui: WalkUiState = emptyUiState();
  private listener: ((s: WalkUiState) => void) | null = null;

  // client null = offline mode: templates only
  constructor(pois: Poi[], interests: Interest[], client: SegmentClient | null, output: NarrationOutput, clock: Clock) {
    this.director = new GuideDirector(pois, interests, client !== null);
    this.client = client;
    this.output = output;
    this.clock = clock;
    for (const p of pois) {
      this.poiById.set(p.id, p);
    }
  }

  onChange(listener: (s: WalkUiState) => void): void {
    this.listener = listener;
  }

  state(): WalkUiState {
    return this.ui;
  }

  onFix(fix: GeoFix): void {
    this.handle(GuideEvents.fix(fix));
  }

  // Call about once per second while the walk is active.
  tick(): void {
    this.handle(GuideEvents.tick(this.clock.now()));
  }

  playbackFinished(segmentId: string): void {
    this.handle(GuideEvents.playbackFinished(segmentId, this.clock.now()));
  }

  acceptDeepDive(): void {
    if (this.ui.deepDiveOfferId.length > 0) {
      this.handle(GuideEvents.deepDiveAccepted(this.ui.deepDiveOfferId, this.clock.now()));
    }
  }

  // WalkSession went to PAUSED (app in background, screen off): stop talking.
  pause(): void {
    this.output.stop();
  }

  private handle(e: GuideEvent): void {
    let actions: GuideAction[] = [];
    try {
      actions = this.director.step(e);
    } catch (err) {
      // the engine must never take the app down: skip this event, keep walking
      actions = [];
    }
    for (const a of actions) {
      this.execute(a);
    }
    this.refresh();
  }

  private execute(a: GuideAction): void {
    if (a.kind === GuideActionKind.PLAY_SEGMENT && a.segment !== null) {
      this.showSegment(a.segment);
      this.output.play(a.segment);
    } else if (a.kind === GuideActionKind.REQUEST_SEGMENT && a.request !== null && this.client !== null) {
      const client = this.client;
      client.request(a.request, a.deadlineT).then((s: Segment | null) => {
        if (s !== null) {
          this.handle(GuideEvents.segmentReady(s, this.clock.now()));
        }
      }).catch(() => {
        // network errors are expected: the template covers it
      });
    } else if (a.kind === GuideActionKind.OFFER_DEEP_DIVE && a.poiId !== null) {
      const p = this.poiById.get(a.poiId);
      this.ui.deepDiveOfferId = a.poiId;
      this.ui.deepDiveOfferName = p !== undefined ? displayName(p) : '';
    } else if (a.kind === GuideActionKind.WITHDRAW_DEEP_DIVE) {
      this.ui.deepDiveOfferId = '';
      this.ui.deepDiveOfferName = '';
    }
  }

  private showSegment(s: Segment): void {
    const p = this.poiById.get(s.poiId);
    this.ui.currentText = s.text;
    this.ui.segmentKind = s.kind;
    this.ui.poiName = p !== undefined ? displayName(p) : '';
    this.ui.sourceUrl = s.sourceUrls.length > 0 ? s.sourceUrls[0] : '';
    this.ui.originLabel = s.origin === SegmentOrigin.AI
      ? 'AI · ' + (s.llmModel !== null ? s.llmModel : 'model') + (s.voice !== null ? ' · ' + s.voice : '')
      : 'szablon';
    if (s.kind === SegmentKind.DEEP_DIVE) {
      this.ui.deepDiveOfferId = '';
      this.ui.deepDiveOfferName = '';
    }
  }

  private refresh(): void {
    const motion = this.director.motion();
    const planner = this.director.plannerState();
    const position = motion.position;
    const next: Stop | null = planner.nextStop;
    this.ui.moving = motion.state === MotionState.MOVING;
    this.ui.storiesTold = planner.spokenStopIds.length;
    if (next !== null && position !== null) {
      this.ui.nextPoiName = displayName(next.anchor);
      this.ui.distanceM = Math.round(distanceToStop(position, next));
      this.ui.etaSeconds = Math.round(planner.nextEtaS);
      const b = bearingDeg(position, next.anchor);
      this.ui.bearingAngle = Math.round(motion.headingDeg !== null ? angleDiffDeg(motion.headingDeg, b) : b);
    } else {
      this.ui.nextPoiName = '';
      this.ui.distanceM = 0;
      this.ui.etaSeconds = 0;
      this.ui.bearingAngle = 0;
    }
    this.ui.laterStops = planner.upcomingMain.slice(1, 5).map((s: Stop) => displayName(s.anchor));
    if (this.listener !== null) {
      this.listener(this.ui);
    }
  }
}
