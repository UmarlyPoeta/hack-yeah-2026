import { GeoFix } from '../model/GeoPoint';

// Source of location fixes for a walk (issue #48). Live GPS on the device, or the demo route
// replayed for the emulator/demo (clearly labelled as a simulation in the UI).
export interface LocationProvider {
  readonly simulated: boolean;
  // onError gets a BusinessError code (e.g. 3301100 = location switch off)
  start(onFix: (fix: GeoFix) => void, onError: (code: number) => void): void;
  stop(): void;
}
