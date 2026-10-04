import { GuideProgress } from '../guide/NarrationPlanner';

// Link between two devices running the same app (phone + watch) so they act as one guide.
// Implementations: RelayLink (through our server, emulators), DistributedLink (distributedDataObject,
// real devices on one Huawei account). The guide only sees this interface. Contract: docs/CONTRACTS.md.
// Privacy: no position, distance or bearing ever goes over the link (issue #56).

export enum LinkMessageKind {
  HELLO = 'hello',        // "I am here" (sent on connect and periodically)
  STATE = 'state',        // LEAD → FOLLOW: what to show
  CMD = 'cmd',            // FOLLOW → LEAD: what the user pressed
  PROGRESS = 'progress'   // old LEAD → new LEAD on a handoff
}

export enum LinkCommand {
  PAUSE = 'pause',
  RESUME = 'resume',
  SKIP = 'skip',
  REPLAY = 'replay',
  DEEP_DIVE = 'deepDive',
  HANDOFF = 'handoff'     // "let me lead"
}

export interface LinkState {
  currentText: string;
  segmentKind: string;
  poiName: string;
  poiId: string;          // id of the place (public data, not a position)
  originLabel: string;
  sourceUrl: string;
  nextPoiName: string;
  laterStops: string[];
  storiesTold: number;
  deepDiveOfferId: string;
  deepDiveOfferName: string;
  paused: boolean;
}

export interface LinkMessage {
  kind: LinkMessageKind;
  from: string;           // sender device id
  seq: number;            // per sender, increasing
  t: number;              // sender clock, ms (informational only)
  state: LinkState | null;
  cmd: LinkCommand | null;
  progress: GuideProgress | null;
}

export interface DeviceLink {
  send(message: LinkMessage): void;
  onMessage(listener: (message: LinkMessage) => void): void;
  close(): void;
}
