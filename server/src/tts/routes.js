// GET /v1/audio/<audioId>.mp3: MP3 from the audio cache (the id comes from Segment.audioUrl).
import { HttpError } from '../http/http.js';

/** @param {import('./TtsService.js').AudioStore | null} store */
export function audioRoutes(store) {
  return [
    {
      method: 'GET',
      path: /^\/v1\/audio\/(?<id>[a-f0-9]{8,64})\.mp3$/,
      handler: async (_req, res, { params }) => {
        const mp3 = store?.read(params.id);
        if (!mp3) throw new HttpError(404, 'not_found', `no audio ${params.id}`);
        res.writeHead(200, {
          'Content-Type': 'audio/mpeg',
          'Content-Length': mp3.length,
          'Cache-Control': 'public, max-age=31536000, immutable',   // the id is a hash of voice + text
        });
        res.end(mp3);
      },
    },
  ];
}
