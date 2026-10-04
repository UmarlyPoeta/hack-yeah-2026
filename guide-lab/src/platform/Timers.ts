// Node version of the timer helpers (in the app: platform/Timers.ets, where setInterval returns a number).
export function startInterval(fn: () => void, ms: number): number {
  return setInterval(fn, ms) as unknown as number;
}

export function stopInterval(id: number): void {
  clearInterval(id as unknown as NodeJS.Timeout);
}
