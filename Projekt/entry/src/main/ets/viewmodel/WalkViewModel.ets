import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { GeoFix } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { Interest } from '../model/Segment';
import { DeviceLink } from '../link/DeviceLink';
import { requestLocationOnce } from '../location/LocationPermission';
import { LocationProvider } from '../location/LocationProvider';
import { APP_BACKGROUND_EVENT, APP_FOREGROUND_EVENT } from '../platform/AppLifecycle';
import { LiveViewPublisher } from '../platform/LiveViewPublisher';
import { SessionReason, SessionState, WalkSession } from '../session/WalkSession';
import { HapticOutput } from './Haptics';
import { Clock, NarrationOutput, SegmentClient, WalkController, WalkUiState } from './WalkController';

// System clock in ms. The LocationProvider stamps GeoFix.t with the same clock.
export class SystemClock implements Clock {
  now(): number {
    return Date.now();
  }
}

export interface WalkOptions {
  pois: Poi[];
  interests: Interest[];
  client: SegmentClient | null;        // null = offline: templates only
  output: NarrationOutput;
  provider: LocationProvider;          // LiveLocationProvider or RouteReplayProvider (simulation)
  context: common.UIAbilityContext;
  haptics: HapticOutput | null;        // VibratorHaptics on the watch (and optionally the phone)
  liveView: boolean;                   // phone: true (ignored where the service does not exist)
}

// Screen state of a walk for ArkUI. All logic lives in WalkController and WalkSession (tested in
// guide-lab); this class wires them to the platform and mirrors their state into @Trace fields.
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
  // session (#48)
  @Trace sessionState: string = SessionState.IDLE;
  @Trace sessionReason: string = SessionReason.NONE;
  @Trace simulated: boolean = false;   // the location comes from a replayed route: show "SYMULACJA"
  // two devices (#50)
  @Trace role: string = 'SOLO';
  @Trace peerConnected: boolean = false;
  @Trace narrationPaused: boolean = false;

  private controller: WalkController | null = null;
  private session: WalkSession = new WalkSession();
  private provider: LocationProvider | null = null;
  private context: common.UIAbilityContext | null = null;
  private liveView: LiveViewPublisher | null = null;
  private timerId: number = -1;
  private listening: boolean = false;

  // --- full walk: permission → location → guide (StartPage/WalkPage)

  async startWalk(o: WalkOptions): Promise<void> {
    this.stop();
    const controller = new WalkController(o.pois, o.interests, o.client, o.output, new SystemClock());
    controller.setHaptics(o.haptics);
    controller.onChange((s: WalkUiState) => this.apply(s));
    this.controller = controller;
    this.provider = o.provider;
    this.context = o.context;
    this.simulated = o.provider.simulated;
    this.liveView = o.liveView && LiveViewPublisher.supported() ? new LiveViewPublisher(o.context) : null;
    if (this.liveView !== null) {
      const lv = this.liveView;
      controller.onChange((s: WalkUiState) => lv.update(s, this.sessionState !== SessionState.WALKING));
    }
    this.session = new WalkSession();
    this.listenToLifecycle();
    this.active = true;
    this.timerId = setInterval(() => this.onTick(), 1000);
    this.session.start(Date.now());
    this.syncSession();
    await this.askAndStart();
  }

  // PAUSED or ERROR → try again. The system shows the dialog only if the one-time grant has expired
  // (it lasts while the app process lives); location itself was stopped by us while in the background.
  async resumeWalk(): Promise<void> {
    if (this.session.resume(Date.now())) {
      this.syncSession();
      await this.askAndStart();
    }
  }

  pauseWalk(): void {
    if (this.session.pause(Date.now())) {
      this.onSessionChanged();
    }
  }

  // --- debug replay without session (GuideDebugPage): kept as before

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
    if (this.provider !== null) {
      this.provider.stop();
    }
    if (this.controller !== null) {
      this.controller.setSessionActive(false);
      this.controller.disconnect();
    }
    if (this.liveView !== null) {
      this.liveView.stop();
    }
    this.stopListening();
    this.session.stop(Date.now());
    this.syncSession();
    this.controller = null;
    this.provider = null;
    this.liveView = null;
    this.active = false;
  }

  // --- what the user presses (on this device or, through the link, on the other one)

  onFix(fix: GeoFix): void {
    if (this.controller !== null) {
      this.controller.onFix(fix);
    }
  }

  playbackFinished(segmentId: string): void {
    this.controller?.playbackFinished(segmentId);
  }

  acceptDeepDive(): void {
    this.controller?.acceptDeepDive();
  }

  pauseNarration(): void {
    this.controller?.pauseNarration();
  }

  resumeNarration(): void {
    this.controller?.resumeNarration();
  }

  skip(): void {
    this.controller?.skip();
  }

  replay(): void {
    this.controller?.replay();
  }

  takeOver(): void {
    this.controller?.takeOver();
  }

  // lead = this device started the walk; the other joins as FOLLOW (#50, link from #51)
  connect(link: DeviceLink, deviceId: string, lead: boolean): void {
    this.controller?.connect(link, deviceId, lead);
  }

  // legacy name used by the debug page
  pause(): void {
    this.controller?.pause();
  }

  // --- internals

  private async askAndStart(): Promise<void> {
    const context = this.context;
    if (context === null) {
      return;
    }
    // a replayed route needs no permission: nothing real is read
    const granted = this.simulated ? true : await requestLocationOnce(context);
    this.session.permissionResult(granted, Date.now());
    this.onSessionChanged();
  }

  private onTick(): void {
    if (this.session.tick(Date.now())) {
      this.onSessionChanged();
    }
    this.controller?.tick();
  }

  private onSessionChanged(): void {
    const provider = this.provider;
    if (provider !== null) {
      if (this.session.wantsLocation()) {
        provider.start((fix: GeoFix) => this.onLocation(fix), (code: number) => this.onLocationError(code));
      } else {
        provider.stop();
      }
    }
    this.controller?.setSessionActive(this.session.state === SessionState.WALKING
      || this.session.state === SessionState.ACQUIRING);
    this.syncSession();
  }

  private onLocation(fix: GeoFix): void {
    if (this.session.fix(fix.t)) {
      this.syncSession();
      this.controller?.setSessionActive(true);
    }
    this.controller?.onFix(fix);
  }

  private onLocationError(code: number): void {
    if (this.session.locationError(code, Date.now())) {
      this.onSessionChanged();
    }
  }

  private listenToLifecycle(): void {
    if (this.listening) {
      return;
    }
    this.listening = true;
    emitter.on(APP_BACKGROUND_EVENT, () => {
      // no location in the background: the walk pauses and the provider stops (the grant itself may live on)
      if (this.session.background(Date.now())) {
        this.onSessionChanged();
      }
    });
    emitter.on(APP_FOREGROUND_EVENT, () => {
      this.syncSession();   // the user decides when to resume (it asks for location again)
    });
  }

  private stopListening(): void {
    if (this.listening) {
      emitter.off(APP_BACKGROUND_EVENT);
      emitter.off(APP_FOREGROUND_EVENT);
      this.listening = false;
    }
  }

  private syncSession(): void {
    this.sessionState = this.session.state;
    this.sessionReason = this.session.reason;
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
    this.role = s.role;
    this.peerConnected = s.peerConnected;
    this.narrationPaused = s.narrationPaused;
  }
}
