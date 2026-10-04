import { GeoFix } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { Interest, Segment, SegmentKind, SegmentOrigin } from '../model/Segment';
import { angleDiffDeg, bearingDeg, relativePosition } from '../guide/geo';
import { GuideDirector, GuideEvent, GuideEvents } from '../guide/GuideDirector';
import { Side } from '../guide/Itinerary';
import { GuideAction, GuideActionKind, GuideProgress, SegmentRequest } from '../guide/NarrationPlanner';
import { MotionState } from '../guide/MotionTracker';
import { distanceToStop, Stop } from '../guide/Stops';
import { displayName } from '../guide/Templates';
import { DeviceLink, LinkCommand, LinkMessage, LinkMessageKind, LinkState } from '../link/DeviceLink';
import { cueForSide, HapticCue, HapticOutput } from './Haptics';

// Connects the guide engine to the outside world through small ports, and keeps the screen state the
// walk page draws. No ArkUI here: WalkViewModel.ets wraps this class with @ObservedV2 for the UI, and
// tests drive it with fakes.
//
// Two devices (phone + watch, issue #50): one is LEAD (computes, speaks, publishes what to show), the
// other FOLLOW (shows it, sends the user's commands). A FOLLOW still runs its own engine, muted, so it
// has its own arrow and distance from its own GPS and can take over at once ("Przejmij") from the
// progress the LEAD hands over. Without a link a device is SOLO.

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

export enum DeviceRole {
  SOLO = 'SOLO',
  LEAD = 'LEAD',
  FOLLOW = 'FOLLOW'
}

export const STATE_HEARTBEAT_MS: number = 3000;   // LEAD re-sends its state at least this often
export const PEER_TIMEOUT_MS: number = 10000;     // no message for this long = the other device is gone

// Exactly the fields WalkPage draws (see its "mock until WalkViewModel" state), plus the device role.
export interface WalkUiState {
  currentText: string;          // what is being said now (teleprompter)
  segmentKind: string;          // WELCOME / APPROACH / ARRIVAL / ...
  poiName: string;              // place the current segment is about
  poiId: string;
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
  role: string;                 // DeviceRole
  peerConnected: boolean;
  narrationPaused: boolean;     // user pressed pause (on this or the other device)
}

export function emptyUiState(): WalkUiState {
  const s: WalkUiState = {
    currentText: '', segmentKind: '', poiName: '', poiId: '', originLabel: '', sourceUrl: '', nextPoiName: '',
    distanceM: 0, etaSeconds: 0, bearingAngle: 0, laterStops: [], moving: false, deepDiveOfferId: '',
    deepDiveOfferName: '', storiesTold: 0, role: DeviceRole.SOLO, peerConnected: false, narrationPaused: false
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
  private listeners: ((s: WalkUiState) => void)[] = [];
  private haptics: HapticOutput | null = null;

  private role: DeviceRole = DeviceRole.SOLO;
  private link: DeviceLink | null = null;
  private deviceId: string = '';
  private seq: number = 0;
  private lastPeerT: number = 0;
  private lastSentState: string = '';
  private lastSentT: number = 0;
  private userPaused: boolean = false;
  private sessionActive: boolean = true;
  private remoteSegmentKey: string = '';

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

  // Adds a listener; several are allowed (screen, Live View, the link).
  onChange(listener: (s: WalkUiState) => void): void {
    this.listeners.push(listener);
  }

  setHaptics(haptics: HapticOutput | null): void {
    this.haptics = haptics;
  }

  state(): WalkUiState {
    return this.ui;
  }

  progress(): GuideProgress {
    return this.director.exportProgress();
  }

  // App Continuation or a restored session: continue from what another device already told.
  restoreProgress(p: GuideProgress): void {
    this.director.importProgress(p);
    this.refresh();
  }

  onFix(fix: GeoFix): void {
    this.handle(GuideEvents.fix(fix));
  }

  // Call about once per second while the walk is active.
  tick(): void {
    const now = this.clock.now();
    this.checkPeer(now);
    this.handle(GuideEvents.tick(now));
  }

  playbackFinished(segmentId: string): void {
    this.handle(GuideEvents.playbackFinished(segmentId, this.clock.now()));
  }

  // --- user commands: run here when this device leads, otherwise go to the LEAD

  acceptDeepDive(): void {
    if (this.role === DeviceRole.FOLLOW) {
      this.sendCommand(LinkCommand.DEEP_DIVE);
    } else if (this.ui.deepDiveOfferId.length > 0) {
      this.handle(GuideEvents.deepDiveAccepted(this.ui.deepDiveOfferId, this.clock.now()));
    }
  }

  pauseNarration(): void {
    if (this.role === DeviceRole.FOLLOW) {
      this.sendCommand(LinkCommand.PAUSE);
      return;
    }
    this.userPaused = true;
    this.output.stop();
    this.applyMute();
  }

  resumeNarration(): void {
    if (this.role === DeviceRole.FOLLOW) {
      this.sendCommand(LinkCommand.RESUME);
      return;
    }
    this.userPaused = false;
    this.applyMute();
  }

  skip(): void {
    if (this.role === DeviceRole.FOLLOW) {
      this.sendCommand(LinkCommand.SKIP);
      return;
    }
    this.output.stop();
    this.runActions(this.safe(() => this.director.skip(this.clock.now())));
  }

  replay(): void {
    if (this.role === DeviceRole.FOLLOW) {
      this.sendCommand(LinkCommand.REPLAY);
      return;
    }
    this.output.stop();
    this.runActions(this.safe(() => this.director.replay(this.clock.now())));
  }

  // "Przejmij": this FOLLOW asks the LEAD to hand over.
  takeOver(): void {
    if (this.role === DeviceRole.FOLLOW) {
      this.sendCommand(LinkCommand.HANDOFF);
    }
  }

  // WalkSession left WALKING (background, grant expired, location off): stop talking, keep planning.
  setSessionActive(active: boolean): void {
    this.sessionActive = active;
    if (!active) {
      this.output.stop();
    }
    this.applyMute();
  }

  pause(): void {
    this.setSessionActive(false);
  }

  // --- link

  // lead = this device started the walk; the other one joins as FOLLOW.
  connect(link: DeviceLink, deviceId: string, lead: boolean): void {
    this.link = link;
    this.deviceId = deviceId;
    this.role = lead ? DeviceRole.LEAD : DeviceRole.FOLLOW;
    this.lastPeerT = this.clock.now();
    link.onMessage((m: LinkMessage) => this.onLinkMessage(m));
    this.applyMute();
    this.send(LinkMessageKind.HELLO, null, null, null);
    this.refresh();
  }

  disconnect(): void {
    if (this.link !== null) {
      this.link.close();
    }
    this.link = null;
    this.becomeSolo();
  }

  deviceRole(): DeviceRole {
    return this.role;
  }

  private onLinkMessage(m: LinkMessage): void {
    if (m.from === this.deviceId) {
      return;
    }
    this.lastPeerT = this.clock.now();
    this.ui.peerConnected = true;
    if (m.kind === LinkMessageKind.HELLO && this.role === DeviceRole.LEAD) {
      this.lastSentState = '';          // a new follower: send the full state now
      this.publishState(true);
    } else if (m.kind === LinkMessageKind.STATE && m.state !== null && this.role === DeviceRole.FOLLOW) {
      this.applyRemoteState(m.state);
    } else if (m.kind === LinkMessageKind.CMD && m.cmd !== null && this.role === DeviceRole.LEAD) {
      this.runCommand(m.cmd);
    } else if (m.kind === LinkMessageKind.PROGRESS && m.progress !== null && this.role === DeviceRole.FOLLOW) {
      this.director.importProgress(m.progress);
      this.role = DeviceRole.LEAD;
      this.applyMute();
      this.lastSentState = '';
    }
    this.refresh();
  }

  private runCommand(cmd: LinkCommand): void {
    if (cmd === LinkCommand.PAUSE) {
      this.pauseNarration();
    } else if (cmd === LinkCommand.RESUME) {
      this.resumeNarration();
    } else if (cmd === LinkCommand.SKIP) {
      this.skip();
    } else if (cmd === LinkCommand.REPLAY) {
      this.replay();
    } else if (cmd === LinkCommand.DEEP_DIVE) {
      this.acceptDeepDive();
    } else if (cmd === LinkCommand.HANDOFF) {
      // hand over what was told, then stop talking and follow
      this.send(LinkMessageKind.PROGRESS, null, null, this.director.exportProgress());
      this.output.stop();
      this.role = DeviceRole.FOLLOW;
      this.applyMute();
    }
  }

  private applyRemoteState(s: LinkState): void {
    const key = s.segmentKind + '|' + s.poiId + '|' + s.currentText.length;
    const isNewSegment = key !== this.remoteSegmentKey;
    this.remoteSegmentKey = key;
    this.ui.currentText = s.currentText;
    this.ui.segmentKind = s.segmentKind;
    this.ui.poiName = s.poiName;
    this.ui.poiId = s.poiId;
    this.ui.originLabel = s.originLabel;
    this.ui.sourceUrl = s.sourceUrl;
    this.ui.storiesTold = s.storiesTold;
    this.ui.deepDiveOfferId = s.deepDiveOfferId;
    this.ui.deepDiveOfferName = s.deepDiveOfferName;
    this.ui.narrationPaused = s.paused;
    if (isNewSegment) {
      // the LEAD names the place; the side comes from this device's own position and heading
      this.cueFor(s.segmentKind, this.poiById.get(s.poiId));
    }
  }

  private checkPeer(now: number): void {
    if (this.link === null || !this.ui.peerConnected) {
      return;
    }
    if (now - this.lastPeerT > PEER_TIMEOUT_MS) {
      this.ui.peerConnected = false;
      if (this.role === DeviceRole.FOLLOW) {
        // the LEAD is gone: go on alone from what this device saw (its own muted engine)
        this.role = DeviceRole.SOLO;
        this.applyMute();
      }
    }
    if (this.role === DeviceRole.LEAD) {
      this.publishState(false);
    }
  }

  private becomeSolo(): void {
    this.role = DeviceRole.SOLO;
    this.ui.peerConnected = false;
    this.applyMute();
    this.refresh();
  }

  private sendCommand(cmd: LinkCommand): void {
    this.send(LinkMessageKind.CMD, null, cmd, null);
  }

  private send(kind: LinkMessageKind, state: LinkState | null, cmd: LinkCommand | null, progress: GuideProgress | null): void {
    if (this.link === null) {
      return;
    }
    this.seq++;
    const m: LinkMessage = {
      kind: kind, from: this.deviceId, seq: this.seq, t: this.clock.now(), state: state, cmd: cmd, progress: progress
    };
    try {
      this.link.send(m);
    } catch (e) {
      // a broken link must not stop the guide; the peer timeout will notice
    }
  }

  // No position, distance or bearing in the state: only what to show (privacy, issue #56).
  private publishState(force: boolean): void {
    if (this.link === null || this.role !== DeviceRole.LEAD) {
      return;
    }
    const s: LinkState = {
      currentText: this.ui.currentText, segmentKind: this.ui.segmentKind, poiName: this.ui.poiName, poiId: this.ui.poiId,
      originLabel: this.ui.originLabel, sourceUrl: this.ui.sourceUrl, nextPoiName: this.ui.nextPoiName,
      laterStops: this.ui.laterStops.slice(), storiesTold: this.ui.storiesTold,
      deepDiveOfferId: this.ui.deepDiveOfferId, deepDiveOfferName: this.ui.deepDiveOfferName,
      paused: this.userPaused
    };
    const json = JSON.stringify(s);
    const now = this.clock.now();
    if (!force && json === this.lastSentState && now - this.lastSentT < STATE_HEARTBEAT_MS) {
      return;
    }
    this.lastSentState = json;
    this.lastSentT = now;
    this.send(LinkMessageKind.STATE, s, null, null);
  }

  // Speak only as SOLO or LEAD, while the session is walking and the user has not paused.
  private applyMute(): void {
    const muted = this.role === DeviceRole.FOLLOW || this.userPaused || !this.sessionActive;
    this.ui.narrationPaused = this.userPaused;
    this.ui.role = this.role;
    if (this.director.isMuted() !== muted) {
      this.runActions(this.safe(() => this.director.setMuted(muted, this.clock.now())));
    }
  }

  // --- engine

  private handle(e: GuideEvent): void {
    this.runActions(this.safe(() => this.director.step(e)));
  }

  // the engine must never take the app down: a failing event is skipped, the walk goes on
  private safe(run: () => GuideAction[]): GuideAction[] {
    try {
      return run();
    } catch (err) {
      return [];
    }
  }

  private runActions(actions: GuideAction[]): void {
    for (const a of actions) {
      this.execute(a);
    }
    this.refresh();
  }

  private execute(a: GuideAction): void {
    if (a.kind === GuideActionKind.PLAY_SEGMENT && a.segment !== null) {
      this.showSegment(a.segment);
      this.output.play(a.segment);
      this.cueFor(a.segment.kind, this.poiById.get(a.segment.poiId));
    } else if (a.kind === GuideActionKind.REQUEST_SEGMENT && a.request !== null && this.client !== null
      && this.role !== DeviceRole.FOLLOW) {
      const client = this.client;
      client.request(a.request, a.deadlineT).then((s: Segment | null) => {
        if (s !== null) {
          this.handle(GuideEvents.segmentReady(s, this.clock.now()));
        }
      }).catch(() => {
        // network errors are expected: the template covers it
      });
    } else if (a.kind === GuideActionKind.OFFER_DEEP_DIVE && a.poiId !== null && this.role !== DeviceRole.FOLLOW) {
      const p = this.poiById.get(a.poiId);
      this.ui.deepDiveOfferId = a.poiId;
      this.ui.deepDiveOfferName = p !== undefined ? displayName(p) : '';
    } else if (a.kind === GuideActionKind.WITHDRAW_DEEP_DIVE && this.role !== DeviceRole.FOLLOW) {
      this.ui.deepDiveOfferId = '';
      this.ui.deepDiveOfferName = '';
    }
  }

  private showSegment(s: Segment): void {
    const p = this.poiById.get(s.poiId);
    this.ui.currentText = s.text;
    this.ui.segmentKind = s.kind;
    this.ui.poiName = p !== undefined ? displayName(p) : '';
    this.ui.poiId = s.poiId;
    this.ui.sourceUrl = s.sourceUrls.length > 0 ? s.sourceUrls[0] : '';
    this.ui.originLabel = s.origin === SegmentOrigin.AI
      ? 'AI · ' + (s.llmModel !== null ? s.llmModel : 'model') + (s.voice !== null ? ' · ' + s.voice : '')
      : 'szablon';
    if (s.kind === SegmentKind.DEEP_DIVE) {
      this.ui.deepDiveOfferId = '';
      this.ui.deepDiveOfferName = '';
    }
  }

  // APPROACH: "look left/right/ahead" from this device's position and heading; ARRIVAL: "you are here".
  private cueFor(kind: string, poi: Poi | undefined): void {
    if (this.haptics === null) {
      return;
    }
    if (kind === SegmentKind.ARRIVAL) {
      this.haptics.cue(HapticCue.ARRIVED);
    } else if (kind === SegmentKind.APPROACH) {
      this.haptics.cue(cueForSide(poi !== undefined ? this.sideOf(poi) : Side.AHEAD));
    }
  }

  private sideOf(poi: Poi): Side {
    const motion = this.director.motion();
    if (motion.position === null || motion.headingDeg === null) {
      return Side.AHEAD;
    }
    const cross = relativePosition(motion.position, motion.headingDeg, poi).crossM;
    return cross > 5 ? Side.RIGHT : (cross < -5 ? Side.LEFT : Side.AHEAD);
  }

  private refresh(): void {
    const motion = this.director.motion();
    const planner = this.director.plannerState();
    const position = motion.position;
    const next: Stop | null = planner.nextStop;
    this.ui.moving = motion.state === MotionState.MOVING;
    this.ui.role = this.role;
    if (this.role !== DeviceRole.FOLLOW) {
      this.ui.storiesTold = planner.spokenStopIds.length;
    }
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
    this.publishState(false);
    for (const l of this.listeners) {
      l(this.ui);
    }
  }
}
