import { GeoFix } from '../model/GeoPoint';
import { LocationProvider } from './LocationProvider';

// SIMULATION: replays a recorded route (bundled demo route) at `speed`× real time. Fix times are
// re-stamped with Date.now() so the engine sees a live walk. Shown as "SYMULACJA" in the UI.
export class RouteReplayProvider implements LocationProvider {
  readonly simulated: boolean = true;
  private route: GeoFix[];
  private speed: number;
  private timerId: number = -1;
  private next: number = 0;
  private startReal: number = 0;

  constructor(route: GeoFix[], speed: number) {
    this.route = route;
    this.speed = Math.max(1, speed);
  }

  start(onFix: (fix: GeoFix) => void, onError: (code: number) => void): void {
    this.stop();
    if (this.route.length === 0) {
      onError(-1);
      return;
    }
    // continue where it stopped (pause/resume), shifting the clock so there is no jump
    const routeOffset = this.next < this.route.length ? this.route[this.next].t : 0;
    this.startReal = Date.now() - routeOffset / this.speed;
    this.timerId = setInterval(() => {
      const routeNow = (Date.now() - this.startReal) * this.speed;
      while (this.next < this.route.length && this.route[this.next].t <= routeNow) {
        const r = this.route[this.next];
        const fix: GeoFix = { lat: r.lat, lon: r.lon, accuracyM: r.accuracyM, t: Date.now() };
        onFix(fix);
        this.next++;
      }
    }, 200);
  }

  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }
}
