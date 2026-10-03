// "Mapa" tab: static map of the route with numbered stops, drawn on a Canvas in the style of
// docs/design/w-drodze.html. Preview only (no Map Kit, no navigation).
import { Fonts } from '../../common/Fonts';
import { Route } from '../../model/Route';

const PADDING: number = 48;

@Component
export struct MapView {
  route: Route | null = null;
  @StorageProp('topInset') topInset: number = 0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.map_bg'))
        .onReady(() => this.draw())

      Column({ space: 2 }) {
        Text($r('app.string.map_title'))
          .fontSize($r('app.float.font_title'))
          .fontFamily(Fonts.EXTRABOLD)
          .fontColor($r('app.color.text'))
        Text(this.route !== null ? `${this.route.title} · ${this.route.distanceLabel()}` : '')
          .fontSize($r('app.float.font_small'))
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.map_hint'))
          .fontSize($r('app.float.font_caption'))
          .fontFamily(Fonts.REGULAR)
          .fontColor($r('app.color.text_muted'))
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .borderRadius(20)
      .backgroundColor($r('app.color.surface'))
      .shadow({ radius: 10, color: $r('app.color.shadow_card'), offsetY: 2 })
      .margin({ left: 12, right: 12, top: this.topInset + 8 })
    }
    .width('100%')
    .height('100%')
  }

  private draw(): void {
    const c = this.ctx;
    const route = this.route;
    if (route === null || c.width <= 0) {
      return;
    }
    const w = c.width;
    const h = c.height;
    c.clearRect(0, 0, w, h);

    // background: a loose grid of town blocks like on the walk map
    c.fillStyle = this.col($r('app.color.map_block'));
    for (let x = -20; x < w; x += 74) {
      for (let y = 0; y < h; y += 58) {
        c.fillRect(x, y, 64, 48);
      }
    }

    // project the stops into the free area below the title card
    const top = this.topInset + 110;
    const bottom = h - 40;
    let minLat = 90;
    let maxLat = -90;
    let minLon = 180;
    let maxLon = -180;
    for (const s of route.stops) {
      minLat = Math.min(minLat, s.lat);
      maxLat = Math.max(maxLat, s.lat);
      minLon = Math.min(minLon, s.lon);
      maxLon = Math.max(maxLon, s.lon);
    }
    const k = Math.cos(maxLat * Math.PI / 180);
    const spanX = Math.max((maxLon - minLon) * k, 1e-6);
    const spanY = Math.max(maxLat - minLat, 1e-6);
    const scale = Math.min((w - 2 * PADDING) / spanX, (bottom - top - PADDING) / spanY);
    const offX = (w - spanX * scale) / 2;
    const offY = top + (bottom - top - spanY * scale) / 2;
    const xs: number[] = route.stops.map((s) => offX + (s.lon - minLon) * k * scale);
    const ys: number[] = route.stops.map((s) => offY + (maxLat - s.lat) * scale);

    // route: white casing, then the accent line
    this.polyline(xs, ys, this.col($r('app.color.map_road')), 11);
    this.polyline(xs, ys, this.col($r('app.color.accent')), 6);

    // numbered stops with names
    for (let i = 0; i < route.stops.length; i++) {
      c.beginPath();
      c.arc(xs[i], ys[i], 13, 0, Math.PI * 2);
      c.fillStyle = this.col($r('app.color.map_road'));
      c.fill();
      c.lineWidth = 2.5;
      c.strokeStyle = this.col($r('app.color.accent'));
      c.stroke();
      c.fillStyle = this.col($r('app.color.accent'));
      c.font = `12vp ${Fonts.BOLD}`;
      c.textAlign = 'center';
      c.textBaseline = 'middle';
      c.fillText(`${route.stops[i].num}`, xs[i], ys[i] + 0.5);

      // label on the side away from the nearest other stop, so neighbouring labels do not collide
      let nearest = -1;
      let best = Number.MAX_VALUE;
      for (let j = 0; j < xs.length; j++) {
        const d = Math.hypot(xs[j] - xs[i], ys[j] - ys[i]);
        if (j !== i && d < best) {
          best = d;
          nearest = j;
        }
      }
      const labelLeft = nearest >= 0 && Math.abs(xs[nearest] - xs[i]) > 20 ? xs[nearest] > xs[i] : xs[i] > w * 0.55;
      c.font = `12vp ${Fonts.SEMIBOLD}`;
      c.textAlign = labelLeft ? 'right' : 'left';
      c.fillStyle = this.col($r('app.color.map_label_place'));
      c.fillText(route.stops[i].name, xs[i] + (labelLeft ? -20 : 20), ys[i]);
    }
  }

  private polyline(xs: number[], ys: number[], color: string, width: number): void {
    const c = this.ctx;
    c.strokeStyle = color;
    c.lineWidth = width;
    c.lineCap = 'round';
    c.lineJoin = 'round';
    c.beginPath();
    c.moveTo(xs[0], ys[0]);
    for (let i = 1; i < xs.length; i++) {
      c.lineTo(xs[i], ys[i]);
    }
    c.stroke();
  }

  /** Colour token from resources as a Canvas colour string. */
  private col(res: Resource): string {
    const argb = this.getUIContext().getHostContext()?.resourceManager.getColorSync(res.id) ?? 0xFF000000;
    return `rgba(${(argb >>> 16) & 0xFF}, ${(argb >>> 8) & 0xFF}, ${argb & 0xFF}, ${(((argb >>> 24) & 0xFF) / 255).toFixed(3)})`;
  }
}
