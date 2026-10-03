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

/** Line drawing of the demo route, like the map in a printed guide. The route draws itself once, then the start pulses. */
@Component
export struct RouteMap {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timer: number = -1;
  private startedAt: number = 0;
  private xs: number[] = [];
  private ys: number[] = [];
  private cum: number[] = [];   // cumulative path length at each waypoint

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.layout();
        this.startedAt = Date.now();
        clearInterval(this.timer);
        this.timer = setInterval(() => this.frame(), 16);
      })
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  private layout(): void {
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
    this.xs = ROUTE.map((s: Stop) => offX + (s.lon - minLon) * k * scale);
    this.ys = ROUTE.map((s: Stop) => offY + (maxLat - s.lat) * scale);
    this.cum = [0];
    for (let i = 1; i < ROUTE.length; i++) {
      const dx = this.xs[i] - this.xs[i - 1];
      const dy = this.ys[i] - this.ys[i - 1];
      this.cum.push(this.cum[i - 1] + Math.sqrt(dx * dx + dy * dy));
    }
  }

  private frame(): void {
    const t = Date.now() - this.startedAt;
    const DELAY = 350;
    const DRAW = 1600;
    const raw = Math.min(1, Math.max(0, (t - DELAY) / DRAW));
    const progress = 1 - Math.pow(1 - raw, 3);   // ease-out cubic
    const pulse = raw >= 1 ? ((t - DELAY - DRAW) % 2200) / 2200 : -1;
    this.draw(progress, pulse);
  }

  private draw(progress: number, pulse: number): void {
    const c = this.ctx;
    const w = c.width;
    const h = c.height;
    const xs = this.xs;
    const ys = this.ys;
    const total = this.cum[this.cum.length - 1];
    const reach = total * progress;
    c.clearRect(0, 0, w, h);

    // faint survey grid
    c.strokeStyle = Palette.RULE;
    c.lineWidth = 0.5;
    for (let gx = 0; gx < w; gx += 24) {
      c.beginPath();
      c.moveTo(gx, 0);
      c.lineTo(gx, h);
      c.stroke();
    }
    for (let gy = 0; gy < h; gy += 24) {
      c.beginPath();
      c.moveTo(0, gy);
      c.lineTo(w, gy);
      c.stroke();
    }

    // route, drawn up to `reach`
    c.strokeStyle = Palette.INK;
    c.lineWidth = 2.5;
    c.lineCap = 'round';
    c.lineJoin = 'round';
    c.setLineDash([1, 7]);
    c.beginPath();
    c.moveTo(xs[0], ys[0]);
    for (let i = 1; i < xs.length; i++) {
      if (this.cum[i] <= reach) {
        c.lineTo(xs[i], ys[i]);
      } else {
        const f = (reach - this.cum[i - 1]) / (this.cum[i] - this.cum[i - 1]);
        c.lineTo(xs[i - 1] + (xs[i] - xs[i - 1]) * f, ys[i - 1] + (ys[i] - ys[i - 1]) * f);
        break;
      }
    }
    c.stroke();
    c.setLineDash([]);

    // pulse ring around the start once the route is drawn
    if (pulse >= 0) {
      c.beginPath();
      c.arc(xs[0], ys[0], 7 + pulse * 16, 0, Math.PI * 2);
      c.lineWidth = 1.5;
      c.strokeStyle = Palette.BRICK;
      c.globalAlpha = 1 - pulse;
      c.stroke();
      c.globalAlpha = 1;
    }

    // labelled stops appear when the line reaches them
    for (let i = 0; i < ROUTE.length; i++) {
      if (ROUTE[i].label.length === 0 || this.cum[i] > reach + 0.5) {
        continue;
      }
      const first = i === 0;
      c.beginPath();
      c.arc(xs[i], ys[i], first ? 7 : 5, 0, Math.PI * 2);
      c.fillStyle = first ? Palette.BRICK : Palette.PAPER;
      c.fill();
      c.lineWidth = 2;
      c.strokeStyle = first ? Palette.BRICK : Palette.INK;
      c.stroke();

      c.font = `15vp ${Fonts.ITALIC}`;
      c.fillStyle = Palette.INK;
      const leftSide = ROUTE[i].labelLeft;
      c.textAlign = leftSide ? 'right' : 'left';
      c.textBaseline = 'middle';
      c.fillText(ROUTE[i].label, xs[i] + (leftSide ? -14 : 14), ys[i]);
    }

    // north mark
    c.fillStyle = Palette.INK_FAINT;
    c.font = `11vp sans-serif`;
    c.textAlign = 'center';
    c.fillText('N', w - 16, 16);
    c.strokeStyle = Palette.INK_FAINT;
    c.lineWidth = 1;
    c.beginPath();
    c.moveTo(w - 16, 26);
    c.lineTo(w - 16, 44);
    c.stroke();
  }
}
