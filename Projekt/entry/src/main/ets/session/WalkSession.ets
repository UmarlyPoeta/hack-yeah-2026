// Lifecycle of one walk: permission, first fix, walking, pause, errors. Pure: the caller feeds events
// with an explicit time and reads `state`/`reason`. docs/ARCHITECTURE.md §5, issue #48.
//
//   IDLE ──start──▶ ASKING ──granted──▶ ACQUIRING ──first fix──▶ WALKING
//                    │ denied              │ 15 s no fix / location off      │ background, grant expired,
//                    ▼                     ▼                                  ▼ location error
//                  ERROR ◀─────────────── ERROR                            PAUSED ──resume──▶ ASKING
//
// The location grant is "Allow this time only". The system keeps it while the app process lives (also in
// the background) and revokes it when the process ends (checked with `atm dump` on the emulator). So the
// app itself stops location when it leaves the foreground (PAUSED), and resuming asks the system again:
// no dialog while the grant is still valid, the dialog again after the process was closed.

export enum SessionState {
  IDLE = 'IDLE',
  ASKING = 'ASKING',          // permission dialog on screen
  ACQUIRING = 'ACQUIRING',    // granted, waiting for the first fix
  WALKING = 'WALKING',
  PAUSED = 'PAUSED',
  ERROR = 'ERROR'
}

export enum SessionReason {
  NONE = 'NONE',
  DENIED = 'DENIED',               // user refused the location permission
  LOCATION_OFF = 'LOCATION_OFF',   // system location switch is off (error 3301100)
  NO_FIX = 'NO_FIX',               // no fix within FIRST_FIX_TIMEOUT_MS
  BACKGROUND = 'BACKGROUND',       // app left the foreground (grant may have expired)
  LOCATION_ERROR = 'LOCATION_ERROR',
  USER = 'USER'                    // user paused or stopped
}

export const FIRST_FIX_TIMEOUT_MS: number = 15000;
export const LOCATION_SWITCH_OFF_CODE: number = 3301100;

export class WalkSession {
  state: SessionState = SessionState.IDLE;
  reason: SessionReason = SessionReason.NONE;
  private acquiringSinceT: number = 0;

  // Each method returns true when the state or reason changed, so the caller knows to refresh.
  start(t: number): boolean {
    if (this.state === SessionState.WALKING || this.state === SessionState.ACQUIRING
      || this.state === SessionState.ASKING) {
      return false;
    }
    return this.go(SessionState.ASKING, SessionReason.NONE, t);
  }

  // PAUSED → ask the system again (dialog only if the one-time grant expired); from ERROR a fresh start.
  resume(t: number): boolean {
    if (this.state !== SessionState.PAUSED && this.state !== SessionState.ERROR) {
      return false;
    }
    return this.go(SessionState.ASKING, SessionReason.NONE, t);
  }

  permissionResult(granted: boolean, t: number): boolean {
    if (this.state !== SessionState.ASKING) {
      return false;
    }
    return granted ? this.go(SessionState.ACQUIRING, SessionReason.NONE, t)
      : this.go(SessionState.ERROR, SessionReason.DENIED, t);
  }

  fix(t: number): boolean {
    if (this.state === SessionState.ACQUIRING) {
      return this.go(SessionState.WALKING, SessionReason.NONE, t);
    }
    return false;
  }

  locationError(code: number, t: number): boolean {
    if (this.state !== SessionState.ACQUIRING && this.state !== SessionState.WALKING) {
      return false;
    }
    const reason = code === LOCATION_SWITCH_OFF_CODE ? SessionReason.LOCATION_OFF : SessionReason.LOCATION_ERROR;
    return this.state === SessionState.WALKING ? this.go(SessionState.PAUSED, reason, t)
      : this.go(SessionState.ERROR, reason, t);
  }

  background(t: number): boolean {
    if (this.state === SessionState.WALKING || this.state === SessionState.ACQUIRING) {
      return this.go(SessionState.PAUSED, SessionReason.BACKGROUND, t);
    }
    return false;
  }

  pause(t: number): boolean {
    if (this.state === SessionState.WALKING || this.state === SessionState.ACQUIRING) {
      return this.go(SessionState.PAUSED, SessionReason.USER, t);
    }
    return false;
  }

  stop(t: number): boolean {
    return this.go(SessionState.IDLE, SessionReason.USER, t);
  }

  tick(t: number): boolean {
    if (this.state === SessionState.ACQUIRING && t - this.acquiringSinceT >= FIRST_FIX_TIMEOUT_MS) {
      return this.go(SessionState.ERROR, SessionReason.NO_FIX, t);
    }
    return false;
  }

  // Location updates are wanted only in these states; outside them the provider must be stopped.
  wantsLocation(): boolean {
    return this.state === SessionState.ACQUIRING || this.state === SessionState.WALKING;
  }

  private go(state: SessionState, reason: SessionReason, t: number): boolean {
    if (state === this.state && reason === this.reason) {
      return false;
    }
    if (state === SessionState.ACQUIRING) {
      this.acquiringSinceT = t;
    }
    this.state = state;
    this.reason = reason;
    return true;
  }
}
