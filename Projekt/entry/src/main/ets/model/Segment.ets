// One piece of narration. Mirrors Segment in docs/CONTRACTS.md.
// String enums keep the values readable in JSON and logs.

export enum SegmentKind {
  WELCOME = 'WELCOME',
  APPROACH = 'APPROACH',
  ARRIVAL = 'ARRIVAL',
  BRIDGE = 'BRIDGE',
  DEEP_DIVE = 'DEEP_DIVE',
  MISSED = 'MISSED'
}

export enum Interest {
  ARCHITECTURE = 'architektura',
  HISTORY = 'historia',
  ART = 'sztuka',
  PEOPLE = 'ludzie',
  LEGENDS = 'legendy'
}

export enum SegmentOrigin {
  AI = 'ai',
  TEMPLATE = 'template'
}

export interface Claim {
  text: string;
  quote: string; // verbatim fragment of the source text
}

export interface Segment {
  id: string;
  kind: SegmentKind;
  poiId: string;
  fromPoiId: string | null;   // BRIDGE only
  text: string;
  claims: Claim[];
  origin: SegmentOrigin;
  llmModel: string | null;
  audioUrl: string | null;
  durationMs: number | null;
  voice: string | null;
  sourceUrls: string[];
  warnings: string[];
}
