import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { pageToPoi, splitSections, USER_AGENT, WikipediaClient } from '../src/pois/wikipedia.js';
import { BARBAKAN, recorded, replayFetch } from './helpers.js';

const client = (fetch) => new WikipediaClient({ apiUrl: 'https://pl.wikipedia.org/w/api.php', timeoutMs: 1000, fetch });

describe('WikipediaClient.geosearch', () => {
  it('follows continuations and merges extracts of all pages', async () => {
    const responses = recorded('geosearch-barbakan.json');
    const fetch = replayFetch(responses);
    const pages = await client(fetch).geosearch(BARBAKAN.lat, BARBAKAN.lon, 300);
    assert.equal(fetch.calls.length, responses.length);
    assert.equal(pages.length, 50);
    const withExtract = pages.filter((p) => p.extract);
    assert.ok(withExtract.length > 20, `only ${withExtract.length} pages have an extract`);
    // continuation params from the previous response are sent with the next request
    assert.ok(new URL(fetch.calls[1]).searchParams.has('excontinue'));
  });

  it('sends a Wikimedia-compliant User-Agent and caps the radius at 10 km', async () => {
    let seen;
    const fetch = async (url, init) => {
      seen = { url: new URL(url), headers: init.headers };
      return new Response(JSON.stringify({ query: { pages: [] } }));
    };
    await client(fetch).geosearch(50, 19, 50000);
    assert.equal(seen.headers['User-Agent'], USER_AGENT);
    assert.match(USER_AGENT, /github\.com/);
    assert.equal(seen.url.searchParams.get('ggsradius'), '10000');
  });

  it('throws on HTTP errors and API errors', async () => {
    await assert.rejects(client(async () => new Response('busy', { status: 503 })).geosearch(50, 19, 100), /503/);
    const apiError = async () => new Response(JSON.stringify({ error: { code: 'ratelimited' } }));
    await assert.rejects(client(apiError).geosearch(50, 19, 100), /ratelimited/);
  });
});

describe('pageToPoi', () => {
  const base = {
    pageid: 1, title: 'Barbakan w Krakowie', extract: 'Barbakan – budowla obronna.',
    coordinates: [{ lat: 50.0655, lon: 19.9417, primary: true, type: 'building', dim: '1000' }],
    pageprops: { wikibase_item: 'Q1' }, thumbnail: { source: 'https://img' }, fullurl: 'https://pl.wikipedia.org/wiki/Barbakan',
  };

  it('maps a page to the Poi contract', () => {
    assert.deepEqual(pageToPoi(base), {
      id: 'plwiki:1', name: 'Barbakan w Krakowie', summary: 'Barbakan – budowla obronna.',
      lat: 50.0655, lon: 19.9417, kind: 'building', wikidataId: 'Q1', imageUrl: 'https://img',
      sourceUrl: 'https://pl.wikipedia.org/wiki/Barbakan',
    });
  });

  it('drops areas, huge objects, pages without text or coordinates', () => {
    const coord = base.coordinates[0];
    assert.equal(pageToPoi({ ...base, coordinates: [{ ...coord, type: 'city' }] }), null);
    assert.equal(pageToPoi({ ...base, coordinates: [{ ...coord, dim: 5000 }] }), null);
    assert.equal(pageToPoi({ ...base, coordinates: [{ ...coord, dim: '20000' }] }), null);
    assert.equal(pageToPoi({ ...base, extract: '  ' }), null);
    assert.equal(pageToPoi({ ...base, extract: undefined }), null);
    assert.equal(pageToPoi({ ...base, coordinates: undefined }), null);
  });

  it('uses the primary coordinate and null for missing optional fields', () => {
    const poi = pageToPoi({
      pageid: 2, title: 'X', extract: 'Tekst.',
      coordinates: [{ lat: 1, lon: 1 }, { lat: 50.1, lon: 19.9, primary: true }],
    });
    assert.equal(poi.lat, 50.1);
    assert.equal(poi.kind, null);
    assert.equal(poi.wikidataId, null);
    assert.equal(poi.imageUrl, null);
    assert.match(poi.sourceUrl, /curid=2/);
  });

  it('keeps no area-type POIs from the recorded Barbakan response', () => {
    const pages = recorded('geosearch-barbakan.json').flatMap((r) => r.body.query.pages);
    const pois = pages.map(pageToPoi).filter(Boolean);
    assert.ok(pois.length > 10);
    assert.ok(pois.some((p) => p.name === 'Barbakan w Krakowie'));
    assert.ok(pois.every((p) => p.id.startsWith('plwiki:') && p.summary && p.sourceUrl));
  });
});

describe('article / splitSections', () => {
  it('returns sections without references, text within 8k chars', async () => {
    const article = await client(replayFetch(recorded('article-sukiennice.json'))).article(19010);
    assert.equal(article.title, 'Sukiennice w Krakowie');
    assert.equal(article.sections[0].title, null);
    assert.ok(article.sections.some((s) => s.title === 'Historia Sukiennic'));
    assert.ok(article.text.length > 1000 && article.text.length <= 8000);
  });

  it('splits on any heading level and drops empty and reference sections', () => {
    const sections = splitSections('Wstęp.\n== Historia ==\nDawno.\n=== Detal ===\nX.\n== Przypisy ==\n[1]\n== Pusta ==\n');
    assert.deepEqual(sections, [
      { title: null, text: 'Wstęp.' },
      { title: 'Historia', text: 'Dawno.' },
      { title: 'Detal', text: 'X.' },
    ]);
  });

  it('returns null for a missing page', async () => {
    const fetch = async () => new Response(JSON.stringify({ query: { pages: [{ pageid: 0, missing: true }] } }));
    assert.equal(await client(fetch).article(0), null);
  });
});
