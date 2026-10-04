// Small file helpers for the stores: JSON files and downloaded photos in the app sandbox (filesDir).
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'LocalFiles';
// Wikimedia asks API clients for a descriptive User-Agent.
const USER_AGENT: string = 'tour-hackyeah2026/0.1 (HarmonyOS walking guide)';
const DOWNLOAD_TIMEOUT_MS: number = 20000;

export function ensureDir(path: string): void {
  if (!fs.accessSync(path)) {
    fs.mkdirSync(path, true);
  }
}

export function readText(path: string): string | null {
  try {
    return fs.accessSync(path) ? fs.readTextSync(path) : null;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read %{public}s failed: %{public}s', path, JSON.stringify(e));
    return null;
  }
}

/** Writes to a temporary file first, so a crash never leaves half a JSON file behind. */
export function writeText(path: string, text: string): void {
  const tmp = `${path}.tmp`;
  try {
    const file = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    fs.writeSync(file.fd, text);
    fs.closeSync(file);
    fs.renameSync(tmp, path);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'write %{public}s failed: %{public}s', path, JSON.stringify(e));
  }
}

export function removeFile(path: string): void {
  try {
    if (path.length > 0 && fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'remove %{public}s failed: %{public}s', path, JSON.stringify(e));
  }
}

export function copyFile(from: string, to: string): boolean {
  try {
    fs.copyFileSync(from, to);
    return true;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'copy %{public}s failed: %{public}s', from, JSON.stringify(e));
    return false;
  }
}

/** GET as text with the Wikimedia User-Agent; null on any failure. */
export async function fetchText(url: string): Promise<string | null> {
  const req = http.createHttp();
  try {
    const res = await req.request(url, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': USER_AGENT, 'Accept': 'application/json' },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: DOWNLOAD_TIMEOUT_MS,
    });
    return res.responseCode === 200 ? res.result as string : null;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'GET %{public}s failed: %{public}s', url, JSON.stringify(e));
    return null;
  } finally {
    req.destroy();
  }
}

/** Downloads url into path; true when the file is complete. */
export async function download(url: string, path: string): Promise<boolean> {
  const req = http.createHttp();
  try {
    const res = await req.request(url, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': USER_AGENT },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 10000,
      readTimeout: DOWNLOAD_TIMEOUT_MS,
    });
    const body = res.result as ArrayBuffer;
    if (res.responseCode !== 200 || body.byteLength === 0) {
      return false;
    }
    const tmp = `${path}.part`;
    const file = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    fs.writeSync(file.fd, body);
    fs.closeSync(file);
    fs.renameSync(tmp, path);
    return true;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'download %{public}s failed: %{public}s', url, JSON.stringify(e));
    return false;
  } finally {
    req.destroy();
  }
}
