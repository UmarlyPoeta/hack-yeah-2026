import { HttpResult, HttpTransport, TextSource } from '../../main/ets/data/HttpTransport';

export interface FakeCall {
  method: string;
  url: string;
  body: string;
}

export interface FakeReply {
  delayMs: number;
  status: number;
  body: string;
  fail: boolean;
}

export function reply(status: number, body: string, delayMs: number = 0): FakeReply {
  const r: FakeReply = { delayMs: delayMs, status: status, body: body, fail: false };
  return r;
}

export function networkError(delayMs: number = 0): FakeReply {
  const r: FakeReply = { delayMs: delayMs, status: 0, body: '', fail: true };
  return r;
}

/** Answers every call with `next(call)`; records calls. */
export class FakeTransport implements HttpTransport {
  calls: FakeCall[] = [];
  next: (call: FakeCall) => FakeReply;

  constructor(next: (call: FakeCall) => FakeReply) {
    this.next = next;
  }

  get(url: string, timeoutMs: number): Promise<HttpResult> {
    return this.handle('GET', url, '');
  }

  postJson(url: string, body: string, timeoutMs: number): Promise<HttpResult> {
    return this.handle('POST', url, body);
  }

  private handle(method: string, url: string, body: string): Promise<HttpResult> {
    const call: FakeCall = { method: method, url: url, body: body };
    this.calls.push(call);
    const r = this.next(call);
    return new Promise<HttpResult>((resolve: (v: HttpResult) => void, reject: (e: Error) => void) => {
      setTimeout(() => {
        if (r.fail) {
          reject(new Error('network down'));
        } else {
          const res: HttpResult = { status: r.status, body: r.body };
          resolve(res);
        }
      }, r.delayMs);
    });
  }
}

export class StringSource implements TextSource {
  private text: string;

  constructor(text: string) {
    this.text = text;
  }

  read(): Promise<string> {
    return Promise.resolve(this.text);
  }
}

export function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
