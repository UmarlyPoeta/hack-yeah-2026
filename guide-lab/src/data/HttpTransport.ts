// Minimal HTTP abstraction, so PoiRepository and SegmentService are testable without a network.
// The real implementation (Network Kit) is NetworkHttpTransport.ets.
export interface HttpResult {
  status: number;
  body: string;
}

export interface HttpTransport {
  /** Rejects on network errors and timeouts; any HTTP status resolves. */
  get(url: string, timeoutMs: number): Promise<HttpResult>;

  postJson(url: string, body: string, timeoutMs: number): Promise<HttpResult>;
}

/** Reads a bundled text file (rawfile in the app, a string in tests). */
export interface TextSource {
  read(): Promise<string>;
}
