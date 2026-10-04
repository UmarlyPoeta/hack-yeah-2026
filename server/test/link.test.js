// Phone <-> watch relay (#51): order, polling with `after`, 200-message cap, 10 min TTL, size limit,
// no positions on the link, request validation.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { createApp } from '../src/http/app.js';
import { LinkRelay, MAX_MESSAGES, TTL_MS } from '../src/link/LinkRelay.js';
import { linkRoutes } from '../src/link/routes.js';
import { failingFetch, fakeClock, listen, makeService } from './helpers.js';

describe('LinkRelay', () => {
  it('numbers messages per room and returns only those after a seq', () => {
    const relay = new LinkRelay({ now: fakeClock() });
    assert.deepEqual(relay.post('1234', 'phone', { type: 'segment' }).seq, 1);
    relay.post('1234', 'watch', { type: 'pause' });
    relay.post('9999', 'phone', { type: 'other room' });
    const { messages, lastSeq } = relay.list('1234', 1);
    assert.equal(lastSeq, 2);
    assert.deepEqual(messages.map((m) => [m.seq, m.from, m.body.type]), [[2, 'watch', 'pause']]);
    assert.deepEqual(relay.list('0000'), { messages: [], lastSeq: 0 });
  });

  it('keeps the last 200 messages of a room', () => {
    const relay = new LinkRelay({ now: fakeClock() });
    for (let i = 0; i < MAX_MESSAGES + 5; i++) relay.post('1234', 'phone', { i });
    const { messages, lastSeq } = relay.list('1234');
    assert.equal(messages.length, MAX_MESSAGES);
    assert.equal(messages[0].seq, 6);
    assert.equal(lastSeq, MAX_MESSAGES + 5);
  });

  it('drops messages after 10 minutes and forgets empty rooms', () => {
    const clock = fakeClock();
    const relay = new LinkRelay({ now: clock });
    relay.post('1234', 'phone', { n: 1 });
    clock.t += TTL_MS - 1000;
    relay.post('1234', 'phone', { n: 2 });
    clock.t += 2000;
    assert.deepEqual(relay.list('1234').messages.map((m) => m.body.n), [2]);
    clock.t += TTL_MS;
    assert.equal(relay.list('1234').messages.length, 0);
    assert.equal(relay.rooms.size, 0);
  });
});

describe('/v1/link HTTP', () => {
  let app;
  let logs;
  before(async () => {
    logs = [];
    const relay = new LinkRelay({ now: fakeClock() });
    app = await listen(createApp({ poiService: makeService({ fetch: failingFetch() }), routes: linkRoutes(relay), log: (m) => logs.push(m) }));
  });
  after(() => app.close());

  const post = async (room, body) => {
    const res = await fetch(`${app.base}/v1/link/${room}/messages`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: typeof body === 'string' ? body : JSON.stringify(body) });
    return { status: res.status, body: await res.json() };
  };
  const get = async (room, query = '') => {
    const res = await fetch(`${app.base}/v1/link/${room}/messages${query}`);
    return { status: res.status, body: await res.json() };
  };

  it('phone posts, watch polls with after', async () => {
    assert.deepEqual((await post('4821', { from: 'phone', body: { type: 'segment', poiId: 'plwiki:19617', text: 'Barbakan.' } })).body.seq, 1);
    assert.equal((await post('4821', { from: 'watch', body: { type: 'pause' } })).status, 200);
    const all = await get('4821');
    assert.equal(all.status, 200);
    assert.deepEqual(all.body.messages.map((m) => m.from), ['phone', 'watch']);
    assert.deepEqual((await get('4821', '?after=1')).body.messages.map((m) => m.body.type), ['pause']);
  });

  it('refuses positions anywhere in the message', async () => {
    const r = await post('4821', { from: 'phone', body: { type: 'state', next: { name: 'Barbakan', lat: 50.06, lon: 19.94 } } });
    assert.equal(r.status, 400);
    assert.equal(r.body.error.code, 'position_not_allowed');
  });

  it('413 for a body over 4 KB', async () => {
    const r = await post('4821', { from: 'phone', body: { text: 'x'.repeat(5000) } });
    assert.equal(r.status, 413);
  });

  for (const [name, room, body] of [
    ['missing from', '4821', { body: {} }],
    ['bad from', '4821', { from: 'PHONE!', body: {} }],
    ['body not an object', '4821', { from: 'phone', body: 'hej' }],
    ['not JSON', '4821', 'nie json'],
  ]) {
    it(`400: ${name}`, async () => {
      assert.equal((await post(room, body)).status, 400);
    });
  }

  it('400 for a bad after, 404 for a bad room id', async () => {
    assert.equal((await get('4821', '?after=-1')).status, 400);
    assert.equal((await get('4821', '?after=abc')).status, 400);
    assert.equal((await get('zły%20pokój')).status, 404);
  });

  it('the log has the path only, never message contents', () => {
    assert.ok(logs.some((l) => l.startsWith('POST /v1/link/4821/messages 200')));
    assert.ok(logs.every((l) => !l.includes('Barbakan.')));
  });
});
