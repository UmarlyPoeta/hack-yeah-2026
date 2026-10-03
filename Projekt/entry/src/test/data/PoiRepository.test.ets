import { describe, expect, it } from '@ohos/hypium';
import { GeoFix } from '../../main/ets/model/GeoFix';
import { Poi, PoiRole } from '../../main/ets/model/Poi';
import { PoiRepository } from '../../main/ets/data/PoiRepository';
import { FakeCall, FakeReply, FakeTransport, networkError, reply, StringSource } from './Fakes';

const BARBAKAN: GeoFix = { lat: 50.06553, lon: 19.9417, accuracyM: 5, t: 0 };
// ~200 m south of Barbakan, past the 150 m refetch distance
const FLORIANSKA: GeoFix = { lat: 50.06373, lon: 19.9417, accuracyM: 5, t: 1000 };
// ~45 m north of the first query, still within the refetch distance
const NEAR_BARBAKAN: GeoFix = { lat: 50.06593, lon: 19.9417, accuracyM: 5, t: 500 };

function poi(id: string, name: string, lat: number, lon: number): Poi {
  const p: Poi = {
    id: id, name: name, summary: `${name}.`, lat: lat, lon: lon, kind: 'building',
    wikidataId: null, imageUrl: null, sourceUrl: `https://pl.wikipedia.org/?curid=${id}`,
    importance: 0.5, role: PoiRole.SIGHT, partOfId: null,
  };
  return p;
}

const SERVER_POIS: Poi[] = [
  poi('plwiki:18947', 'Brama Floriańska w Krakowie', 50.064861, 19.941389),
  poi('plwiki:19617', 'Barbakan w Krakowie', 50.065556, 19.941667),
];
const FIXTURE_POIS: Poi[] = [
  poi('plwiki:19617', 'Barbakan w Krakowie', 50.065556, 19.941667),
  poi('plwiki:19010', 'Sukiennice w Krakowie', 50.061667, 19.937222),
];

interface PoisBody {
  pois: Poi[];
  source: string;
}

interface FixtureBody {
  pois: Poi[];
}

function serverBody(source: string): string {
  const b: PoisBody = { pois: SERVER_POIS, source: source };
  return JSON.stringify(b);
}

function fixtures(): StringSource {
  const f: FixtureBody = { pois: FIXTURE_POIS };
  return new StringSource(JSON.stringify(f));
}

function repo(next: (call: FakeCall) => FakeReply): PoiRepository {
  return new PoiRepository(new FakeTransport(next), 'http://10.0.0.5:8787/', fixtures(), 1000);
}

export default function poiRepositoryTest() {
  describe('PoiRepository', () => {
    it('server_ok_returns_sorted_pois_with_distance', 0, async () => {
      const t = new FakeTransport(() => reply(200, serverBody('live')));
      const r = new PoiRepository(t, 'http://10.0.0.5:8787/', fixtures(), 1000);
      const pois = await r.near(BARBAKAN, 300);
      expect(r.lastSource).assertEqual('live');
      expect(pois.length).assertEqual(2);
      expect(pois[0].name).assertEqual('Barbakan w Krakowie');
      expect((pois[0].distanceM as number) <= (pois[1].distanceM as number)).assertTrue();
      expect(t.calls[0].url).assertEqual('http://10.0.0.5:8787/v1/pois?lat=50.065530&lon=19.941700&radius=300');
    });

    it('server_source_cache_is_reported', 0, async () => {
      const r = repo(() => reply(200, serverBody('cache')));
      await r.near(BARBAKAN, 300);
      expect(r.lastSource).assertEqual('cache');
    });

    it('network_error_falls_back_to_rawfile', 0, async () => {
      const r = repo(() => networkError());
      const pois = await r.near(BARBAKAN, 300);
      expect(r.lastSource).assertEqual('fixture');
      expect(pois.length).assertEqual(1);
      expect(pois[0].id).assertEqual('plwiki:19617');
    });

    it('http_500_and_bad_json_fall_back_to_rawfile', 0, async () => {
      const r1 = repo(() => reply(500, '{"error":{"code":"internal","message":"x"}}'));
      await r1.near(BARBAKAN, 300);
      expect(r1.lastSource).assertEqual('fixture');
      const r2 = repo(() => reply(200, '<html>proxy</html>'));
      await r2.near(BARBAKAN, 300);
      expect(r2.lastSource).assertEqual('fixture');
    });

    it('offline_mode_never_calls_http', 0, async () => {
      const t = new FakeTransport(() => reply(200, serverBody('live')));
      const r = new PoiRepository(t, '', fixtures(), 1000);
      const pois = await r.near(BARBAKAN, 1000);
      expect(t.calls.length).assertEqual(0);
      expect(r.lastSource).assertEqual('fixture');
      expect(pois.length).assertEqual(2);
    });

    it('refetches_only_after_150_m', 0, async () => {
      const t = new FakeTransport(() => reply(200, serverBody('live')));
      const r = new PoiRepository(t, 'http://10.0.0.5:8787', fixtures(), 1000);
      await r.near(BARBAKAN, 300);
      const again = await r.near(NEAR_BARBAKAN, 300);
      expect(t.calls.length).assertEqual(1);
      // distances follow the new position even without a new query
      expect(again[0].name).assertEqual('Barbakan w Krakowie');
      expect((again[0].distanceM as number) > 30).assertTrue();
      await r.near(FLORIANSKA, 300);
      expect(t.calls.length).assertEqual(2);
      await r.near(FLORIANSKA, 500);
      expect(t.calls.length).assertEqual(3);
    });

    it('filters_by_radius', 0, async () => {
      const r = repo(() => reply(200, serverBody('live')));
      const pois = await r.near(BARBAKAN, 50);
      expect(pois.length).assertEqual(1);
      expect(pois[0].name).assertEqual('Barbakan w Krakowie');
    });

    it('get_finds_poi_from_last_result_or_fixtures', 0, async () => {
      const r = repo(() => reply(200, serverBody('live')));
      await r.near(BARBAKAN, 300);
      expect((await r.get('plwiki:18947'))?.name).assertEqual('Brama Floriańska w Krakowie');
      expect((await r.get('plwiki:19010'))?.name).assertEqual('Sukiennice w Krakowie');
      expect(await r.get('plwiki:1')).assertNull();
    });

    it('broken_rawfile_gives_empty_list_not_crash', 0, async () => {
      const r = new PoiRepository(null, '', new StringSource('not json'), 1000);
      const pois = await r.near(BARBAKAN, 300);
      expect(pois.length).assertEqual(0);
    });
  });
}
