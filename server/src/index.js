// Entry point: `npm start` (reads server/.env if present).
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { JsonCache } from './cache/JsonCache.js';
import { loadConfig, VERSION } from './config.js';
import { createApp } from './http/app.js';
import { LinkRelay } from './link/LinkRelay.js';
import { linkRoutes } from './link/routes.js';
import { loadFixturePois, PoiService } from './pois/PoiService.js';
import { WikidataClient } from './pois/wikidata.js';
import { WikipediaClient } from './pois/wikipedia.js';

const config = loadConfig();
const log = (msg) => console.log(`${new Date().toISOString()} ${msg}`);

const poiService = new PoiService({
  wiki: new WikipediaClient({ apiUrl: config.wikiApiUrl, timeoutMs: config.wikiTimeoutMs }),
  wikidata: new WikidataClient({ apiUrl: config.wikidataApiUrl, timeoutMs: config.wikiTimeoutMs }),
  areaCache: new JsonCache({ file: path.join(config.cacheDir, 'pois-areas.json'), ttlMs: config.poiCacheTtlMs }),
  articleCache: new JsonCache({ file: path.join(config.cacheDir, 'articles.json'), ttlMs: 7 * config.poiCacheTtlMs }),
  fixturePois: loadFixturePois(config.fixturePoisPath),
  log,
});

const server = http.createServer(createApp({ poiService, routes: linkRoutes(new LinkRelay()), log }));

server.listen(config.port, config.host, () => {
  log(`spacer-z-historia server ${VERSION} listening on port ${config.port}`);
  log(`  local:    http://localhost:${config.port}/v1/health`);
  for (const addr of lanAddresses()) log(`  LAN:      http://${addr}:${config.port}/v1/health`);
  log(`  fixtures: ${poiService.fixturePois.length} POIs, cache dir ${config.cacheDir}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    server.closeAllConnections();
  });
}

function lanAddresses() {
  return Object.values(os.networkInterfaces())
    .flat()
    .filter((a) => a && a.family === 'IPv4' && !a.internal)
    .map((a) => a.address);
}
