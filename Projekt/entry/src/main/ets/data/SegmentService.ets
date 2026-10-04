// Client of POST /v1/segment with the planner's deadline.
// - request(): the server's segment if it arrives before the deadline, otherwise a local template right away.
// - A late server answer is cached and announced through onUpgrade(); the caller may swap it in if the
//   template has not been played yet.
// - prefetch(): starts a request early (REQUEST_SEGMENT action of GuideDirector: ARRIVAL(next), BRIDGE(cur->next)).
// - At most `maxParallel` requests at once (Bielik on a CPU is the bottleneck). Queued requests whose
//   deadline has already passed are dropped before they reach the server.
import { Interest, Segment, SegmentKind } from '../model/Segment';
import { HttpTransport } from './HttpTransport';

export interface SegmentRequest {
  kind: SegmentKind;
  poiId: string;
  fromPoiId: string | null;
  interests: Interest[];
  maxWords: number;
  voice: boolean;
}

/** Local text without AI for any request (implemented by guide/Templates.ets, P2). */
export interface SegmentFallback {
  build(req: SegmentRequest): Segment;
}

export type SegmentUpgradeListener = (key: string, segment: Segment) => void;

export interface SegmentServiceOptions {
  maxParallel: number;
  timeoutMs: number;           // HTTP timeout for normal segments
  deepDiveTimeoutMs: number;   // HTTP timeout for DEEP_DIVE
  now: () => number;
}

class Job {
  key: string;
  req: SegmentRequest;
  expiresAt: number;
  result: Promise<Segment | null>;
  resolve: (s: Segment | null) => void = () => {};

  constructor(key: string, req: SegmentRequest, expiresAt: number) {
    this.key = key;
    this.req = req;
    this.expiresAt = expiresAt;
    this.result = new Promise<Segment | null>((resolve: (s: Segment | null) => void) => {
      this.resolve = resolve;
    });
  }
}

export class SegmentService {
  private http: HttpTransport | null;
  private baseUrl: string;
  private fallback: SegmentFallback;
  private options: SegmentServiceOptions;
  private ready: Map<string, Segment> = new Map<string, Segment>();
  private jobs: Map<string, Job> = new Map<string, Job>();
  private queue: Job[] = [];
  private running: number = 0;
  private servedFallback: Set<string> = new Set<string>();
  private listeners: SegmentUpgradeListener[] = [];

  /** http = null or empty baseUrl: offline mode, every request returns the local template. */
  constructor(http: HttpTransport | null, baseUrl: string, fallback: SegmentFallback,
    options: SegmentServiceOptions) {
    this.http = http;
    this.baseUrl = baseUrl.replace(new RegExp('/+$'), '');
    this.fallback = fallback;
    this.options = options;
  }

  static keyOf(req: SegmentRequest): string {
    const interests = req.interests.slice().sort().join(',');
    return `${req.kind}|${req.poiId}|${req.fromPoiId ?? ''}|${interests}|${req.maxWords}|${req.voice ? 1 : 0}`;
  }

  /** Called when a server segment arrives after its template was already handed out. */
  onUpgrade(listener: SegmentUpgradeListener): void {
    this.listeners.push(listener);
  }

  /** Starts fetching in the background; a later request() with the same input reuses it. */
  prefetch(req: SegmentRequest, deadlineMs: number): void {
    if (this.isOnline() && !this.ready.has(SegmentService.keyOf(req))) {
      this.ensureJob(req, deadlineMs);
    }
  }

  /** deadlineMs: time from now after which the local template is used. Never rejects. */
  async request(req: SegmentRequest, deadlineMs: number): Promise<Segment> {
    const key = SegmentService.keyOf(req);
    const cached = this.ready.get(key);
    if (cached !== undefined) {
      return cached;
    }
    if (!this.isOnline() || deadlineMs <= 0) {
      return this.useFallback(key, req);
    }
    const job = this.ensureJob(req, deadlineMs);
    let timer: number = -1;
    const timeout = new Promise<Segment | null>((resolve: (s: Segment | null) => void) => {
      timer = setTimeout(() => resolve(null), deadlineMs);
    });
    const first = await Promise.race<Segment | null>([job.result, timeout]);
    clearTimeout(timer);
    return first !== null ? first : this.useFallback(key, req);
  }

  /** Number of requests sent and not answered yet (for the UI / tests). */
  get inFlight(): number {
    return this.running;
  }

  private isOnline(): boolean {
    return this.http !== null && this.baseUrl.length > 0;
  }

  private useFallback(key: string, req: SegmentRequest): Segment {
    if (this.jobs.has(key)) {
      this.servedFallback.add(key);
    }
    return this.fallback.build(req);
  }

  private ensureJob(req: SegmentRequest, deadlineMs: number): Job {
    const key = SegmentService.keyOf(req);
    const expiresAt = this.options.now() + deadlineMs;
    const existing = this.jobs.get(key);
    if (existing !== undefined) {
      existing.expiresAt = Math.max(existing.expiresAt, expiresAt);
      return existing;
    }
    const job = new Job(key, req, expiresAt);
    this.jobs.set(key, job);
    this.queue.push(job);
    this.pump();
    return job;
  }

  private pump(): void {
    while (this.running < this.options.maxParallel && this.queue.length > 0) {
      const job = this.queue.shift() as Job;
      if (this.options.now() >= job.expiresAt) {
        this.finish(job, null);   // nobody waits any more: do not spend Bielik time on it
        continue;
      }
      this.running++;
      this.send(job.req).then((segment: Segment | null) => {
        this.running--;
        this.finish(job, segment);
        this.pump();
      });
    }
  }

  private finish(job: Job, segment: Segment | null): void {
    this.jobs.delete(job.key);
    if (segment !== null) {
      this.ready.set(job.key, segment);
      if (this.servedFallback.has(job.key)) {
        for (const listener of this.listeners) {
          listener(job.key, segment);
        }
      }
    }
    this.servedFallback.delete(job.key);
    job.resolve(segment);
  }

  /** Server segment, or null on any failure (network, status, bad body). */
  private async send(req: SegmentRequest): Promise<Segment | null> {
    const timeoutMs = req.kind === SegmentKind.DEEP_DIVE ? this.options.deepDiveTimeoutMs : this.options.timeoutMs;
    try {
      const res = await (this.http as HttpTransport).postJson(`${this.baseUrl}/v1/segment`, JSON.stringify(req),
        timeoutMs);
      if (res.status !== 200) {
        return null;
      }
      const segment = JSON.parse(res.body) as Segment;
      if (typeof segment.text !== 'string' || segment.text.length === 0 || segment.kind !== req.kind) {
        return null;
      }
      if (segment.audioUrl !== null && segment.audioUrl !== undefined && segment.audioUrl.startsWith('/')) {
        segment.audioUrl = this.baseUrl + segment.audioUrl;
      }
      return segment;
    } catch (e) {
      return null;
    }
  }
}
