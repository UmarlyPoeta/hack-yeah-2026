// Entry point: `npm start` (reads server/.env if present).
import http from 'node:http';
import os from 'node:os';
import { loadConfig, VERSION } from './config.js';
import { createApp } from './http/app.js';
import { LinkRelay } from './link/LinkRelay.js';
import { linkRoutes } from './link/routes.js';
import { segmentRoutes } from './segment/routes.js';
import { createServices } from './services.js';
import { audioRoutes } from './tts/routes.js';

const config = loadConfig();
const log = (msg) => console.log(`${new Date().toISOString()} ${msg}`);
const { poiService, llm, tts, segments, health } = createServices(config, log);

const server = http.createServer(createApp({
  poiService,
  health,
  routes: [...segmentRoutes(segments), ...audioRoutes(tts?.store ?? null), ...linkRoutes(new LinkRelay())],
  log,
}));

server.listen(config.port, config.host, () => {
  log(`spacer-z-historia server ${VERSION} listening on port ${config.port}`);
  log(`  local:    http://localhost:${config.port}/v1/health`);
  for (const addr of lanAddresses()) log(`  LAN:      http://${addr}:${config.port}/v1/health`);
  log(`  fixtures: ${poiService.fixturePois.length} POIs, cache dir ${config.cacheDir}`);
  log(`  llm:      ${llm ? `${config.llmModel} at ${config.ollamaUrl}` : 'none (LLM_MODEL empty): segments from templates'}`);
  log(`  tts:      ${tts ? tts.providers.map((p) => `${p.name}${p.available() ? '' : ' (not configured)'}`).join(' -> ') : 'none'}`);
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
