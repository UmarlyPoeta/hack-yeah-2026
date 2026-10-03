// Records real MediaWiki API responses into test/fixtures/ so `npm test` runs without network.
// Usage: npm run record-fixtures   (needs internet)
import { writeFileSync } from 'node:fs';
import { WikipediaClient } from '../src/pois/wikipedia.js';

const OUT = new URL('../test/fixtures/', import.meta.url);
const BARBAKAN = { lat: 50.06553, lon: 19.9417 };
const SUKIENNICE_PAGEID = 19010;

const responses = [];
const recordingFetch = async (url, init) => {
  const res = await fetch(url, init);
  const body = await res.json();
  responses.push({ params: Object.fromEntries(new URL(url).searchParams), body });
  return new Response(JSON.stringify(body), { status: res.status });
};

const wiki = new WikipediaClient({ apiUrl: 'https://pl.wikipedia.org/w/api.php', timeoutMs: 15000, fetch: recordingFetch });

const pages = await wiki.geosearch(BARBAKAN.lat, BARBAKAN.lon, 300);
writeFileSync(new URL('geosearch-barbakan.json', OUT), JSON.stringify(responses, null, 1));
console.log(`geosearch: ${responses.length} responses, ${pages.length} pages`);

responses.length = 0;
const article = await wiki.article(SUKIENNICE_PAGEID);
writeFileSync(new URL('article-sukiennice.json', OUT), JSON.stringify(responses, null, 1));
console.log(`article: ${article?.title}, ${article?.text.length} chars, ${article?.sections.length} sections`);
