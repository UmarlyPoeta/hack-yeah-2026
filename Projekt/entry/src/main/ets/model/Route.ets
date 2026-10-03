// Routes and stops shown by the UI. One model for all screens, so no screen has route text hard-coded.
// MOCK data until routes come from the guide engine / server; photos are placeholders in resources/base/media.
import { distanceM } from '../guide/geo';
import { GeoPoint } from './GeoPoint';

export class RouteStop implements GeoPoint {
  num: number;
  name: string;
  caption: string;
  image: Resource;
  lat: number;
  lon: number;
  summary: string;          // "Więcej o tym miejscu"
  transcript: string[];     // narration, sentence by sentence
  audioSeconds: number;
  approach: string;         // how to get here from the previous stop, shown on the direction card

  constructor(num: number, name: string, caption: string, image: Resource, lat: number, lon: number, summary: string,
    transcript: string[], audioSeconds: number, approach: string) {
    this.num = num;
    this.name = name;
    this.caption = caption;
    this.image = image;
    this.lat = lat;
    this.lon = lon;
    this.summary = summary;
    this.transcript = transcript;
    this.audioSeconds = audioSeconds;
    this.approach = approach;
  }
}

export class Route {
  id: string;
  title: string;
  subtitle: string;
  cover: Resource;
  coverLabel: string;       // what the photo shows, for screen readers
  distanceKm: number;
  durationMin: number;
  stops: RouteStop[];

  constructor(id: string, title: string, subtitle: string, cover: Resource, coverLabel: string, distanceKm: number,
    durationMin: number, stops: RouteStop[]) {
    this.id = id;
    this.title = title;
    this.subtitle = subtitle;
    this.cover = cover;
    this.coverLabel = coverLabel;
    this.distanceKm = distanceKm;
    this.durationMin = durationMin;
    this.stops = stops;
  }

  /** "1,6 km" */
  distanceLabel(): string {
    return `${this.distanceKm.toFixed(1).replace('.', ',')} km`;
  }

  /** Walking distance from the previous stop, e.g. "80 m"; empty for the first stop. */
  legLabel(index: number): string {
    if (index <= 0 || index >= this.stops.length) {
      return '';
    }
    const m = distanceM(this.stops[index - 1], this.stops[index]);
    return m < 1000 ? `${Math.round(m / 10) * 10} m` : `${(m / 1000).toFixed(1).replace('.', ',')} km`;
  }
}

const ROYAL_ROUTE_STOPS: RouteStop[] = [
  new RouteStop(1, 'Barbakan', 'Brama przed bramą', $r('app.media.barbakan'), 50.065556, 19.941667,
    'Barbakan to najbardziej wysunięta na północ część dawnych fortyfikacji Krakowa. Stoi na Plantach, przed Bramą Floriańską.',
    ['Barbakan postawiono w 1499 roku, kiedy w Krakowie bano się najazdu tureckiego.',
      'Mury mają ponad 3 metry grubości.', 'Policz otwory strzelnicze, jest ich 130.'], 220, 'Start przy Plantach'),
  new RouteStop(2, 'Brama Floriańska', 'Ostatnia z ośmiu bram', $r('app.media.brama_florianska'), 50.064861, 19.941389,
    'Średniowieczna brama miejska z basztą, zamyka od północy ulicę Floriańską. Pozostałość dawnych murów miejskich.',
    ['Z ośmiu bram miejskich przetrwała tylko ta jedna.', 'Przez nią królowie wjeżdżali do miasta na koronację.'], 180, 'Prosto przez bramę'),
  new RouteStop(3, 'Kościół Mariacki', 'Hejnał co godzinę', $r('app.media.kosciol_mariacki'), 50.061667, 19.939444,
    'Gotycka bazylika przy Rynku Głównym. W środku ołtarz Wita Stwosza, z wyższej wieży co godzinę grany jest hejnał.',
    ['Hejnał urywa się w połowie melodii.', 'Według legendy trębacza trafiła strzała w gardło.'], 240, 'Ulicą Floriańską do Rynku'),
  new RouteStop(4, 'Sukiennice', 'Środek Rynku', $r('app.media.sukiennice'), 50.061667, 19.937222,
    'Dawna hala targowa na środku Rynku Głównego, dziś z kramami na parterze i galerią sztuki na piętrze.',
    ['W średniowieczu handlowano tu suknem, stąd nazwa.', 'Na piętrze jest galeria malarstwa polskiego XIX wieku.'], 200, 'Przez Rynek na zachód'),
  new RouteStop(5, 'Kościół św. Piotra i Pawła', 'Apostołowie na murze', $r('app.media.kosciol_piotra_pawla'), 50.056944,
    19.938611,
    'Barokowy kościół przy ulicy Grodzkiej. Przed fasadą stoją figury dwunastu apostołów.',
    ['To pierwsza w Polsce budowla wzorowana na rzymskim kościele Il Gesù.', 'Figury apostołów to kopie, oryginały są w muzeum.'],
    190, 'Ulicą Grodzką na południe'),
  new RouteStop(6, 'Wawel', 'Zamek i katedra', $r('app.media.wawel'), 50.054, 19.935278,
    'Wzgórze z Zamkiem Królewskim i Katedrą Wawelską, przez wieki siedziba polskich królów.',
    ['Na Wawelu koronowano i chowano polskich królów.', 'W wieży katedry wisi Dzwon Zygmunt.'], 260, 'Grodzką do wzgórza'),
];

export const ROYAL_ROUTE: Route = new Route('royal-route', 'Droga Królewska', 'Od Barbakanu do Wawelu',
  $r('app.media.barbakan'), 'Barbakan od strony Plant', 1.6, 45, ROYAL_ROUTE_STOPS);

/** "Zapisane" tab: preview only, nothing is actually saved yet. */
export const SAVED_ROUTES: Route[] = [
  ROYAL_ROUTE,
  new Route('wawel-hill', 'Wzgórze Wawelskie', 'Zamek, katedra i Smocza Jama', $r('app.media.wawel'), 'Wawel od strony Wisły',
    1.1, 30, ROYAL_ROUTE_STOPS.slice(4)),
  new Route('market-square', 'Wokół Rynku', 'Sukiennice, Mariacki i kamienice', $r('app.media.sukiennice'),
    'Sukiennice na Rynku Głównym', 0.9, 25, ROYAL_ROUTE_STOPS.slice(2, 4)),
];
