import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { GeoFix } from '../model/GeoPoint';
import { LocationProvider } from './LocationProvider';

// Real GPS, one fix per second in the navigation scenario. Only started after the user granted
// location for this walk; stopped as soon as the walk pauses (no location in the background).
export class LiveLocationProvider implements LocationProvider {
  readonly simulated: boolean = false;
  private callback: ((loc: geoLocationManager.Location) => void) | null = null;

  start(onFix: (fix: GeoFix) => void, onError: (code: number) => void): void {
    this.stop();
    try {
      if (!geoLocationManager.isLocationEnabled()) {
        onError(3301100);
        return;
      }
      const request: geoLocationManager.ContinuousLocationRequest = {
        interval: 1,
        locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION
      };
      const cb = (loc: geoLocationManager.Location): void => {
        // stamped with the app clock, not the GNSS time: the engine compares it with its own ticks
        const fix: GeoFix = { lat: loc.latitude, lon: loc.longitude, accuracyM: loc.accuracy, t: Date.now() };
        onFix(fix);
      };
      this.callback = cb;
      geoLocationManager.on('locationChange', request, cb);
    } catch (e) {
      const err = e as BusinessError;
      onError(err.code !== undefined ? err.code : -1);
    }
  }

  stop(): void {
    if (this.callback === null) {
      return;
    }
    try {
      geoLocationManager.off('locationChange', this.callback);
    } catch (e) {
      // already off
    }
    this.callback = null;
  }
}
