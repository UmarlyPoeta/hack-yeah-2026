import { Fonts, Palette } from '../common/Theme';

class Stop {
  lat: number;
  lon: number;
  label: string;
  labelLeft: boolean;

  constructor(lat: number, lon: number, label: string, labelLeft: boolean = false) {
    this.lat = lat;
    this.lon = lon;
    this.label = label;
    this.labelLeft = labelLeft;
  }
}

// Demo route Barbakan -> Wawel: the same waypoints as tools/gen_fixtures.py.
const ROUTE: Stop[] = [
  new Stop(50.06553, 19.94170, 'Barbakan', true),
  new Stop(50.06490, 19.94145, ''),
  new Stop(50.06340, 19.93990, ''),
  new Stop(50.06190, 19.93920, ''),
  new Stop(50.06155, 19.93730, 'Rynek Główny', true),
  new Stop(50.06000, 19.93780, ''),
  new Stop(50.05790, 19.93820, ''),
  new Stop(50.05650, 19.93870, ''),
  new Stop(50.05470, 19.93560, 'Wawel'),
];

/** Line drawing of the demo route, like the map in a printed guide. */
@Component
export struct RouteMap {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => this.draw())
  }

  private draw(): void {
    const w = this.ctx.width;
    const h = this.ctx.height;
    const pad = 28;
    let minLat = 90;
    let maxLat = -90;
    let minLon = 180;
    let maxLon = -180;
    for (const s of ROUTE) {
      minLat = Math.min(minLat, s.lat);
      maxLat = Math.max(maxLat, s.lat);
      minLon = Math.min(minLon, s.lon);
      maxLon = Math.max(maxLon, s.lon);
    }
    const k = Math.cos(50.06 * Math.PI / 180);   // metres per degree of longitude vs latitude
    const spanX = (maxLon - minLon) * k;
    const spanY = maxLat - minLat;
    const scale = Math.min((w - 2 * pad) / spanX, (h - 2 * pad) / spanY);
    const offX = (w - spanX * scale) / 2;
    const offY = (h - spanY * scale) / 2;
    const xs: number[] = ROUTE.map((s: Stop) => offX + (s.lon - minLon) * k * scale);
    const ys: number[] = ROUTE.map((s: Stop) => offY + (maxLat - s.lat) * scale);

    this.ctx.clearRect(0, 0, w, h);

    // faint survey grid
    this.ctx.strokeStyle = Palette.RULE;
    this.ctx.lineWidth = 0.5;
    for (let gx = 0; gx < w; gx += 24) {
      this.ctx.beginPath();
      this.ctx.moveTo(gx, 0);
      this.ctx.lineTo(gx, h);
      this.ctx.stroke();
    }
    for (let gy = 0; gy < h; gy += 24) {
      this.ctx.beginPath();
      this.ctx.moveTo(0, gy);
      this.ctx.lineTo(w, gy);
      this.ctx.stroke();
    }

    // route
    this.ctx.strokeStyle = Palette.INK;
    this.ctx.lineWidth = 2.5;
    this.ctx.lineCap = 'round';
    this.ctx.lineJoin = 'round';
    this.ctx.setLineDash([1, 7]);
    this.ctx.beginPath();
    this.ctx.moveTo(xs[0], ys[0]);
    for (let i = 1; i < xs.length; i++) {
      this.ctx.lineTo(xs[i], ys[i]);
    }
    this.ctx.stroke();
    this.ctx.setLineDash([]);

    // labelled stops
    for (let i = 0; i < ROUTE.length; i++) {
      if (ROUTE[i].label.length === 0) {
        continue;
      }
      const first = i === 0;
      this.ctx.beginPath();
      this.ctx.arc(xs[i], ys[i], first ? 7 : 5, 0, Math.PI * 2);
      this.ctx.fillStyle = first ? Palette.BRICK : Palette.PAPER;
      this.ctx.fill();
      this.ctx.lineWidth = 2;
      this.ctx.strokeStyle = first ? Palette.BRICK : Palette.INK;
      this.ctx.stroke();

      this.ctx.font = `15vp ${Fonts.ITALIC}`;
      this.ctx.fillStyle = Palette.INK;
      const leftSide = ROUTE[i].labelLeft;
      this.ctx.textAlign = leftSide ? 'right' : 'left';
      this.ctx.textBaseline = 'middle';
      this.ctx.fillText(ROUTE[i].label, xs[i] + (leftSide ? -14 : 14), ys[i]);
    }

    // north mark
    this.ctx.fillStyle = Palette.INK_FAINT;
    this.ctx.font = `11vp sans-serif`;
    this.ctx.textAlign = 'center';
    this.ctx.fillText('N', w - 16, 16);
    this.ctx.strokeStyle = Palette.INK_FAINT;
    this.ctx.lineWidth = 1;
    this.ctx.beginPath();
    this.ctx.moveTo(w - 16, 26);
    this.ctx.lineTo(w - 16, 44);
    this.ctx.stroke();
  }
}
