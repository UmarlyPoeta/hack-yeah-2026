// ArkTS version of the timer helpers (guide-lab has a Node version with the same functions).
export function startInterval(fn: () => void, ms: number): number {
  return setInterval(fn, ms);
}

export function stopInterval(id: number): void {
  clearInterval(id);
}
