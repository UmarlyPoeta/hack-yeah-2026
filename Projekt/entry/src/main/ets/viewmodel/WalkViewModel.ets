import { GeoFix } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { Interest } from '../model/Segment';
import { Clock, NarrationOutput, SegmentClient, WalkController, WalkUiState } from './WalkController';

// System clock in ms. The LocationProvider (P1) must stamp GeoFix.t with the same clock.
export class SystemClock implements Clock {
  now(): number {
    return Date.now();
  }
}

// Screen state of a walk for ArkUI. All logic lives in WalkController (tested in guide-lab);
// this class only mirrors its state into @Trace fields and runs the 1 s tick.
@ObservedV2
export class WalkViewModel {
  @Trace currentText: string = '';
  @Trace segmentKind: string = '';
  @Trace poiName: string = '';
  @Trace originLabel: string = '';
  @Trace sourceUrl: string = '';
  @Trace nextPoiName: string = '';
  @Trace distanceM: number = 0;
  @Trace etaSeconds: number = 0;
  @Trace bearingAngle: number = 0;
  @Trace laterStops: string[] = [];
  @Trace moving: boolean = false;
  @Trace deepDiveOfferId: string = '';
  @Trace deepDiveOfferName: string = '';
  @Trace storiesTold: number = 0;
  @Trace active: boolean = false;

  private controller: WalkController | null = null;
  private timerId: number = -1;

  // client null = offline (templates only). tickMs can be shortened for an accelerated debug replay.
  start(pois: Poi[], interests: Interest[], client: SegmentClient | null, output: NarrationOutput, clock: Clock,
    tickMs: number = 1000): void {
    this.stop();
    const controller = new WalkController(pois, interests, client, output, clock);
    controller.onChange((s: WalkUiState) => this.apply(s));
    this.controller = controller;
    this.active = true;
    this.timerId = setInterval(() => controller.tick(), tickMs);
  }

  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    if (this.controller !== null) {
      this.controller.pause();
    }
    this.controller = null;
    this.active = false;
  }

  onFix(fix: GeoFix): void {
    if (this.controller !== null) {
      this.controller.onFix(fix);
    }
  }

  playbackFinished(segmentId: string): void {
    if (this.controller !== null) {
      this.controller.playbackFinished(segmentId);
    }
  }

  acceptDeepDive(): void {
    if (this.controller !== null) {
      this.controller.acceptDeepDive();
    }
  }

  // WalkSession PAUSED: stop talking, keep the state on screen.
  pause(): void {
    if (this.controller !== null) {
      this.controller.pause();
    }
  }

  private apply(s: WalkUiState): void {
    this.currentText = s.currentText;
    this.segmentKind = s.segmentKind;
    this.poiName = s.poiName;
    this.originLabel = s.originLabel;
    this.sourceUrl = s.sourceUrl;
    this.nextPoiName = s.nextPoiName;
    this.distanceM = s.distanceM;
    this.etaSeconds = s.etaSeconds;
    this.bearingAngle = s.bearingAngle;
    this.laterStops = s.laterStops.slice();
    this.moving = s.moving;
    this.deepDiveOfferId = s.deepDiveOfferId;
    this.deepDiveOfferName = s.deepDiveOfferName;
    this.storiesTold = s.storiesTold;
  }
}
