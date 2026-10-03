// Mirrors `Segment`, `Claim`, `SegmentKind`, `Interest` in docs/CONTRACTS.md.
export type SegmentKind = 'WELCOME' | 'APPROACH' | 'ARRIVAL' | 'BRIDGE' | 'DEEP_DIVE' | 'MISSED';

export type Interest = 'architektura' | 'historia' | 'sztuka' | 'ludzie' | 'legendy';

export interface Claim {
  text: string;
  quote: string;               // verbatim fragment of the source text
}

export interface Segment {
  id: string;
  kind: SegmentKind;
  poiId: string;               // for BRIDGE: the target POI
  fromPoiId: string | null;    // BRIDGE only
  text: string;
  claims: Claim[];
  origin: 'ai' | 'template';
  llmModel: string | null;
  audioUrl: string | null;     // server returns "/v1/audio/<id>.mp3"; SegmentService makes it absolute
  durationMs: number | null;
  voice: string | null;
  sourceUrls: string[];
  warnings: string[];
}
