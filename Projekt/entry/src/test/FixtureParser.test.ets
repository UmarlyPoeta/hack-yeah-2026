import { describe, it, expect } from '@ohos/hypium';
import { DEFAULT_ROUTE_ACCURACY_M, parsePois, parseRoute, ParseResult } from '../main/ets/data/FixtureParser';
import { Poi } from '../main/ets/model/Poi';
import { GeoFix } from '../main/ets/model/GeoPoint';

// Inline JSON: local unit tests run without the app's resource manager, so they cannot read rawfile.
const GOOD_POI: string = '{"id":"plwiki:1","name":"Barbakan","summary":"Fortyfikacja.","lat":50.065514,'
  + '"lon":19.941617,"kind":"","sourceUrl":"https://pl.wikipedia.org/wiki/Barbakan"}';

export default function fixtureParserTest() {
  describe('fixtureParser', () => {
    it('parsePoisSkipsBadEntries', 0, () => {
      const text: string = '{"pois":[' + GOOD_POI + ',' + GOOD_POI + ',{"id":"x"},'
        + '{"id":"plwiki:2","name":"N","summary":"S","lat":123,"lon":20,"sourceUrl":"u"},null]}';
      const r: ParseResult<Poi> = parsePois(text);
      expect(r.error).assertNull();
      expect(r.items.length).assertEqual(1);
      expect(r.rejected).assertEqual(4);   // duplicate, missing fields, lat out of range, null
      expect(r.items[0].kind).assertNull(); // empty string becomes null
    });

    it('parsePoisReportsBrokenFile', 0, () => {
      expect(parsePois('{not json').error).assertEqual('invalid JSON');
      expect(parsePois('{"other": 1}').error).assertEqual('missing "pois" array');
    });

    it('parseRouteConvertsSecondsAndRejectsTimeGoingBack', 0, () => {
      const r: ParseResult<GeoFix> = parseRoute('[{"lat":50,"lon":20,"t":0},{"lat":50,"lon":20,"t":5},'
        + '{"lat":50,"lon":20,"t":3},{"lat":50,"lon":20,"t":5},{"lat":50,"lon":20}]');
      expect(r.items.length).assertEqual(2);
      expect(r.rejected).assertEqual(3);
      expect(r.items[1].t).assertEqual(5000);
      expect(r.items[0].accuracyM).assertEqual(DEFAULT_ROUTE_ACCURACY_M);
      expect(parseRoute('{}').error).assertEqual('route must be a JSON array');
    });
  });
}
