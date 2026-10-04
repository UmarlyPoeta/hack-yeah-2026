// Routes for createApp({ routes }): POST /v1/segment.
import { readJson, sendJson } from '../http/http.js';
import { parseSegmentRequest } from './SegmentGenerator.js';

/** @param {import('./SegmentGenerator.js').SegmentGenerator} generator */
export function segmentRoutes(generator) {
  return [
    {
      method: 'POST',
      path: '/v1/segment',
      handler: async (req, res) => {
        const segmentReq = parseSegmentRequest(await readJson(req));
        sendJson(res, 200, await generator.generate(segmentReq));
      },
    },
  ];
}
