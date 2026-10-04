import { HttpResult, HttpTransport } from '../data/HttpTransport';
import { DeviceLink, LinkMessage } from './DeviceLink';
import { startInterval, stopInterval } from '../platform/Timers';

// DeviceLink through our server's relay (#51): POST /v1/link/<room>/messages, GET ?after=<seq>.
// Works wherever both devices reach the server: emulators and real devices on a USB cable to the laptop
// (`hdc rport tcp:8787 tcp:8787`, URL http://127.0.0.1:8787), or the laptop's LAN address. This is how the
// demo links phone and watch without Super Device (which needs real paired devices on one Huawei account).

export const RELAY_POLL_MS: number = 700;
export const RELAY_TIMEOUT_MS: number = 3000;
export const RELAY_MAX_BYTES: number = 3800;   // the server accepts 4 KB per message, envelope included

interface RelayEnvelope {
  from: string;
  body: LinkMessage;
}

interface RelayItem {
  seq: number;
  from: string;
  body: LinkMessage;
}

interface RelayList {
  messages: RelayItem[];
  lastSeq: number;
}

export class RelayLink implements DeviceLink {
  private http: HttpTransport;
  private url: string;
  private deviceId: string;
  private listener: ((m: LinkMessage) => void) | null = null;
  private afterSeq: number = -1;           // -1: not synced yet, skip the room's history
  private timerId: number = -1;
  private polling: boolean = false;
  private sending: Promise<void> = Promise.resolve();
  private closed: boolean = false;
  online: boolean = false;                 // last request reached the server
  lastError: string = '';

  // deviceId must match [a-z0-9_-]{1,16} (server rule)
  constructor(http: HttpTransport, baseUrl: string, room: string, deviceId: string) {
    this.http = http;
    this.url = baseUrl.replace(new RegExp('/+$'), '') + '/v1/link/' + encodeURIComponent(room) + '/messages';
    this.deviceId = deviceId;
  }

  send(message: LinkMessage): void {
    if (this.closed) {
      return;
    }
    const body = this.fit(message);
    if (body === null) {
      this.lastError = 'message too large';
      return;
    }
    // one request at a time keeps the order of messages
    this.sending = this.sending.then(() => this.post(body));
  }

  onMessage(listener: (message: LinkMessage) => void): void {
    this.listener = listener;
    if (this.timerId < 0 && !this.closed) {
      this.poll();
      this.timerId = startInterval(() => this.poll(), RELAY_POLL_MS);
    }
  }

  close(): void {
    this.closed = true;
    if (this.timerId >= 0) {
      stopInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // Serialised envelope under the server limit; a long story text is shortened (the FOLLOW only shows it).
  private fit(message: LinkMessage): string | null {
    let json = JSON.stringify(this.envelope(message));
    if (this.bytes(json) <= RELAY_MAX_BYTES || message.state === null) {
      return this.bytes(json) <= RELAY_MAX_BYTES ? json : null;
    }
    const state = message.state;
    let text = state.currentText;
    while (this.bytes(json) > RELAY_MAX_BYTES && text.length > 40) {
      text = text.slice(0, Math.floor(text.length * 0.8)) + '…';
      state.currentText = text;
      json = JSON.stringify(this.envelope(message));
    }
    return this.bytes(json) <= RELAY_MAX_BYTES ? json : null;
  }

  private envelope(message: LinkMessage): RelayEnvelope {
    const e: RelayEnvelope = { from: this.deviceId, body: message };
    return e;
  }

  private bytes(s: string): number {
    let n = 0;
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      n += c < 0x80 ? 1 : (c < 0x800 ? 2 : 3);
    }
    return n;
  }

  private async post(body: string): Promise<void> {
    try {
      const r: HttpResult = await this.http.postJson(this.url, body, RELAY_TIMEOUT_MS);
      this.online = r.status === 200;
      this.lastError = r.status === 200 ? '' : 'HTTP ' + r.status;
    } catch (e) {
      this.online = false;
      this.lastError = 'network';
    }
  }

  private async poll(): Promise<void> {
    if (this.polling || this.closed) {
      return;
    }
    this.polling = true;
    try {
      const after = this.afterSeq < 0 ? 0 : this.afterSeq;
      const r: HttpResult = await this.http.get(this.url + '?after=' + after, RELAY_TIMEOUT_MS);
      if (r.status === 200) {
        const list = JSON.parse(r.body) as RelayList;
        this.online = true;
        this.lastError = '';
        const firstSync = this.afterSeq < 0;
        // the room was reset (server restarted, messages expired): start over from its counter
        if (list.lastSeq < this.afterSeq) {
          this.afterSeq = list.lastSeq;
        }
        for (const m of list.messages) {
          if (m.seq > this.afterSeq) {
            this.afterSeq = m.seq;
            // history from before we joined is skipped: the LEAD answers our HELLO with a fresh state
            if (!firstSync && m.from !== this.deviceId && this.listener !== null && m.body !== null) {
              this.listener(m.body);
            }
          }
        }
        if (firstSync) {
          this.afterSeq = Math.max(this.afterSeq, list.lastSeq, 0);
        }
      } else {
        this.online = false;
        this.lastError = 'HTTP ' + r.status;
      }
    } catch (e) {
      this.online = false;
      this.lastError = 'network';
    } finally {
      this.polling = false;
    }
  }
}
