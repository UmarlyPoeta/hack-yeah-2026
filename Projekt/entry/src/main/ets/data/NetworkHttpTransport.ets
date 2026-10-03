import { http } from '@kit.NetworkKit';
import { HttpResult, HttpTransport } from './HttpTransport';

export class NetworkHttpTransport implements HttpTransport {
  get(url: string, timeoutMs: number): Promise<HttpResult> {
    return this.send(url, http.RequestMethod.GET, undefined, timeoutMs);
  }

  postJson(url: string, body: string, timeoutMs: number): Promise<HttpResult> {
    return this.send(url, http.RequestMethod.POST, body, timeoutMs);
  }

  private async send(url: string, method: http.RequestMethod, body: string | undefined,
    timeoutMs: number): Promise<HttpResult> {
    const req = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: Math.min(timeoutMs, 10000),
        readTimeout: timeoutMs,
      };
      const res = await req.request(url, options);
      const result: HttpResult = { status: res.responseCode, body: res.result as string };
      return result;
    } finally {
      req.destroy();
    }
  }
}
