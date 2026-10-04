// Entry point: `npm start` (reads server/.env if present).
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { JsonCache } from './cache/JsonCache.js';
import { loadConfig, VERSION } from './config.js';
import { createApp } from './http/app.js';
import { OllamaClient } from './llm/OllamaClient.js';
import { loadFixturePois, PoiService } from './pois/PoiService.js';
import { WikidataClient } from './pois/wikidata.js';
import { WikipediaClient } from './pois/wikipedia.js';
import { SegmentGenerator } from './segment/SegmentGenerator.js';
import { segmentRoutes } from './segment/routes.js';

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

const llm = config.llmModel
  ? new OllamaClient({ url: config.ollamaUrl, model: config.llmModel, modalKey: config.modalKey, modalSecret: config.modalSecret })
  : null;
const segments = new SegmentGenerator({
  poiService,
  llm,
  cache: new JsonCache({ file: path.join(config.cacheDir, 'segments.json'), ttlMs: 30 * 24 * 3600 * 1000 }),
  timeouts: { default: config.llmTimeoutMs, deepDive: config.llmDeepDiveTimeoutMs },
  log,
});

const server = http.createServer(createApp({
  poiService,
  health: { llm: async () => (llm ? llm.health() : { ok: false, model: '' }) },
  routes: segmentRoutes(segments),
  log,
}));

server.listen(config.port, config.host, () => {
  log(`spacer-z-historia server ${VERSION} listening on port ${config.port}`);
  log(`  local:    http://localhost:${config.port}/v1/health`);
  for (const addr of lanAddresses()) log(`  LAN:      http://${addr}:${config.port}/v1/health`);
  log(`  fixtures: ${poiService.fixturePois.length} POIs, cache dir ${config.cacheDir}`);
  log(`  llm:      ${llm ? `${config.llmModel} at ${config.ollamaUrl}` : 'none (LLM_MODEL empty): segments from templates'}`);
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
