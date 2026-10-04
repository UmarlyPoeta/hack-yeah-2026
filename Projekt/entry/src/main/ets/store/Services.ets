// One PoiRepository and one SegmentService for the whole app, created from the ability context.
import { common } from '@kit.AbilityKit';
import { API_BASE_URL, REQUEST_TIMEOUT_MS, DEEP_DIVE_TIMEOUT_MS } from '../data/ApiConfig';
import { NetworkHttpTransport } from '../data/NetworkHttpTransport';
import { PoiRepository } from '../data/PoiRepository';
import { RawfileTextSource } from '../data/RawfileTextSource';
import { SegmentFallback, SegmentRequest, SegmentService } from '../data/SegmentService';
import { arrivalText, estimateDurationMs, takeWords } from '../guide/Templates';
import { Poi } from '../model/Poi';
import { Segment, SegmentKind, SegmentOrigin } from '../model/Segment';

/** Local text when the server is off or too slow: the first sentences of the Wikipedia intro. */
class SummaryFallback implements SegmentFallback {
  private lookup: (id: string) => Poi | null;

  constructor(lookup: (id: string) => Poi | null) {
    this.lookup = lookup;
  }

  build(req: SegmentRequest): Segment {
    const poi = this.lookup(req.poiId);
    const text = poi === null ? '' :
      (req.kind === SegmentKind.DEEP_DIVE ? takeWords(poi.summary, req.maxWords) : arrivalText(poi, req.maxWords, []));
    const segment: Segment = {
      id: `local-${req.kind}-${req.poiId}`,
      kind: req.kind,
      poiId: req.poiId,
      fromPoiId: req.fromPoiId,
      text: text,
      claims: [],
      origin: SegmentOrigin.TEMPLATE,
      llmModel: null,
      audioUrl: null,
      durationMs: estimateDurationMs(text),
      voice: null,
      sourceUrls: poi === null ? [] : [poi.sourceUrl],
      warnings: ['local_template'],
    };
    return segment;
  }
}

// The place screen waits for Bielik behind the loading screen. A cold Modal container needs about
// 100 s for the first answer, so this is longer than SEGMENT_TIMEOUT_MS of the walk engine.
export const NARRATION_TIMEOUT_MS: number = 150000;

export class Services {
  private static repo: PoiRepository | null = null;
  private static segments: SegmentService | null = null;
  // Pois the fallback can talk about (the app registers every Poi it shows).
  private static known: Map<string, Poi> = new Map<string, Poi>();

  /** baseUrl: the server address from the settings ("Moje" > Serwer), API_BASE_URL by default. */
  static init(context: common.Context, baseUrl: string = API_BASE_URL): void {
    if (Services.repo === null) {
      Services.configure(context, baseUrl);
    }
  }

  /** New server address: new clients, so the next request goes there. */
  static configure(context: common.Context, baseUrl: string): void {
    const http = new NetworkHttpTransport();
    Services.repo = new PoiRepository(http, baseUrl, new RawfileTextSource(context, 'pois-krakow.json'),
      REQUEST_TIMEOUT_MS);
    Services.segments = new SegmentService(http, baseUrl,
      new SummaryFallback((id: string) => Services.known.get(id) ?? null), {
        maxParallel: 2,
        timeoutMs: NARRATION_TIMEOUT_MS,
        deepDiveTimeoutMs: DEEP_DIVE_TIMEOUT_MS,
        now: () => Date.now(),
      });
  }

  static pois(): PoiRepository {
    return Services.repo as PoiRepository;
  }

  static narration(): SegmentService {
    return Services.segments as SegmentService;
  }

  static remember(poi: Poi): void {
    Services.known.set(poi.id, poi);
  }
}
