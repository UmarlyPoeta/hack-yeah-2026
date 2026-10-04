import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  applySignals, classifyByClasses, classifyByName, importanceFromLanglinks, importanceFromSummary, withDefaultSignals,
} from '../src/pois/signals.js';

const poi = (id, name, wikidataId, summary = 'x') => ({
  id, name, summary, lat: 50, lon: 19, kind: null, wikidataId, imageUrl: null, sourceUrl: 'https://pl.wikipedia.org/',
});

describe('importance', () => {
  it('log(1 + langlinks) / log(41), clipped to 1', () => {
    assert.equal(importanceFromLanglinks(0), 0);
    assert.equal(importanceFromLanglinks(40), 1);
    assert.equal(importanceFromLanglinks(400), 1);
    assert.equal(importanceFromLanglinks(19), Math.round(Math.log(20) / Math.log(41) * 1000) / 1000);
    assert.ok(importanceFromLanglinks(35) > importanceFromLanglinks(17));
  });

  it('summary fallback: min(1, chars / 2000)', () => {
    assert.equal(importanceFromSummary('a'.repeat(1000)), 0.5);
    assert.equal(importanceFromSummary('a'.repeat(5000)), 1);
    assert.equal(importanceFromSummary(undefined), 0);
  });
});

describe('role and exclusion', () => {
  it('Wikidata classes: street/square/old town = area, parish/organisation = excluded', () => {
    assert.deepEqual(classifyByClasses(['Q79007']), { role: 'area', excluded: false });
    assert.deepEqual(classifyByClasses(['Q13033698']), { role: 'area', excluded: false });
    assert.deepEqual(classifyByClasses(['Q16970']), { role: 'sight', excluded: false });
    assert.deepEqual(classifyByClasses(['Q102496']), { role: 'sight', excluded: true });
    assert.deepEqual(classifyByClasses(['Q105390172']), { role: 'sight', excluded: true });
    // a museum that Wikidata also calls an organisation has a building: keep it
    assert.deepEqual(classifyByClasses(['Q43229', 'Q33506']), { role: 'sight', excluded: false });
    assert.deepEqual(classifyByClasses([]), { role: 'sight', excluded: false });
  });

  it('name prefixes when Wikidata is unavailable', () => {
    for (const n of ['Ulica Floriańska w Krakowie', 'Plac Mariacki', 'Rynek Główny', 'Stare Miasto w Krakowie',
      'Zaułek Książąt Czartoryskich', 'Mury miejskie w Krakowie', 'Planty w Krakowie']) {
      assert.equal(classifyByName(n).role, 'area', n);
    }
    assert.equal(classifyByName('Sukiennice w Krakowie').role, 'sight');
    assert.equal(classifyByName('Parafia Wniebowzięcia NMP').excluded, true);
  });
});

describe('applySignals', () => {
  const pois = [
    poi('plwiki:1', 'Sukiennice w Krakowie', 'Q1'),
    poi('plwiki:2', 'Galeria w Sukiennicach', 'Q2'),
    poi('plwiki:3', 'Parafia Mariacka', 'Q3'),
    poi('plwiki:4', 'Ulica Floriańska', 'Q4'),
    poi('plwiki:5', 'Kaplica bez Wikidaty', null),
  ];
  const langlinks = new Map([[1, 23], [2, 3], [3, 0], [4, 10]]);
  const claims = new Map([
    ['Q1', { p31: ['Q977382'], p361: [] }],
    ['Q2', { p31: ['Q207694'], p361: ['Q1', 'Q999'] }],
    ['Q3', { p31: ['Q102496'], p361: [] }],
    ['Q4', { p31: ['Q79007'], p361: ['Q3'] }],
  ]);

  it('adds the three fields, drops excluded places, links parts only inside the response', () => {
    const { pois: out, warnings } = applySignals(pois, { langlinks, claims });
    assert.deepEqual(warnings, []);
    assert.deepEqual(out.map((p) => p.id), ['plwiki:1', 'plwiki:2', 'plwiki:4', 'plwiki:5']);
    const get = (id) => out.find((p) => p.id === id);
    assert.equal(get('plwiki:2').partOfId, 'plwiki:1');
    assert.equal(get('plwiki:4').partOfId, null, 'parent was excluded, so no link');
    assert.equal(get('plwiki:4').role, 'area');
    assert.equal(get('plwiki:5').importance, 0, 'no langlinks entry = 0');
    assert.equal(get('plwiki:5').role, 'sight');
  });

  it('reports both fallbacks', () => {
    const { pois: out, warnings } = applySignals(pois, { langlinks: null, claims: null });
    assert.deepEqual(warnings, ['importance_fallback', 'wikidata_unavailable']);
    assert.ok(!out.some((p) => p.name.startsWith('Parafia')), 'parish dropped by name prefix');
    assert.ok(out.every((p) => p.partOfId === null));
  });

  it('withDefaultSignals fills old data and keeps new data untouched', () => {
    const old = withDefaultSignals(poi('plwiki:9', 'Ulica X', null, 'a'.repeat(400)));
    assert.deepEqual([old.importance, old.role, old.partOfId], [0.2, 'area', null]);
    const fresh = { ...old, importance: 0.9, role: 'sight' };
    assert.equal(withDefaultSignals(fresh), fresh);
  });
});
