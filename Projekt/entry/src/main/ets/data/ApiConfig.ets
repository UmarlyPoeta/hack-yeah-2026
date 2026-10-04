// Server address and timeouts. Empty API_BASE_URL = offline mode (bundled data + local templates only).
// Example: 'http://192.168.1.20:8787' (the laptop's LAN address printed by `npm start` in server/).
export const API_BASE_URL: string = 'http://10.0.2.2:8787';   // emulator -> server on this laptop

export const REQUEST_TIMEOUT_MS: number = 20000;

// /v1/segment may wait for Bielik (server LLM timeout 45 s, DEEP_DIVE 90 s). The planner's deadline is
// usually shorter: the guide then speaks a local template, and a late answer can still replace it.
export const SEGMENT_TIMEOUT_MS: number = 50000;
export const DEEP_DIVE_TIMEOUT_MS: number = 95000;
