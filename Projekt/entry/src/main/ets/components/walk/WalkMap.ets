// Static map of the Barbakan area, the SVG from docs/design/w-drodze.html redrawn on a Canvas.
// Drawn in the design's 390-wide coordinates and scaled to the screen. MOCK until a real map exists.
import { Fonts } from '../../common/Fonts';

const DESIGN_WIDTH: number = 390;

@Component
export struct WalkMap {
  /** number shown in the next-stop marker */
  @Prop @Watch('redraw') nextStopNum: number = 2;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.map_bg'))
      .accessibilityText($r('app.string.a11y_walk_map'))
      .onReady(() => this.redraw())
  }

  redraw(): void {
    const c = this.ctx;
    if (c.width <= 0) {
      return;
    }
    const s = c.width / DESIGN_WIDTH;
    c.clearRect(0, 0, c.width, c.height);
    c.save();
    c.scale(s, s);
    const h = c.height / s;

    // city blocks north of Basztowa (the design's rotated pattern)
    c.save();
    c.beginPath();
    c.rect(0, 0, DESIGN_WIDTH, 140);
    c.clip();
    c.rotate(4 * Math.PI / 180);
    c.fillStyle = this.col($r('app.color.map_block'));
    for (let x = -148; x < DESIGN_WIDTH + 74; x += 74) {
      for (let y = -116; y < 200; y += 58) {
        c.fillRect(x, y, 64, 48);
      }
    }
    c.restore();

    // Basztowa street
    c.fillStyle = this.col($r('app.color.map_road'));
    c.fillRect(-10, 138, 410, 20);
    c.strokeStyle = this.col($r('app.color.map_road_dash'));
    c.lineWidth = 1;
    c.setLineDash([6, 4]);
    c.beginPath();
    c.moveTo(-10, 146);
    c.lineTo(400, 146);
    c.stroke();
    c.setLineDash([]);

    // Planty park with paths
    c.fillStyle = this.col($r('app.color.map_park'));
    c.fillRect(-10, 158, 410, 178);
    c.strokeStyle = this.col($r('app.color.map_park_path'));
    c.lineWidth = 4;
    c.beginPath();
    c.moveTo(-10, 230);
    c.bezierCurveTo(80, 214, 150, 232, 200, 236);
    c.bezierCurveTo(260, 240, 320, 222, 400, 228);
    c.stroke();
    c.beginPath();
    c.moveTo(-10, 300);
    c.bezierCurveTo(70, 292, 140, 304, 200, 302);
    c.bezierCurveTo(270, 300, 330, 290, 400, 296);
    c.stroke();
    c.strokeStyle = this.col($r('app.color.map_park_main_path'));
    c.lineWidth = 12;
    c.beginPath();
    c.moveTo(200, 244);
    c.lineTo(200, 336);
    c.stroke();

    // Barbakan
    this.circle(200, 216, 27, this.col($r('app.color.map_barbakan_fill')), this.col($r('app.color.map_barbakan_stroke')), 1.5);
    this.circle(200, 216, 16, this.col($r('app.color.map_barbakan_inner')), '', 0);

    // city walls with towers and the gate
    c.fillStyle = this.col($r('app.color.map_wall'));
    c.fillRect(-10, 334, 410, 9);
    this.tower(64, 328, 16, 18);
    this.tower(128, 328, 14, 18);
    this.tower(268, 328, 14, 18);
    this.tower(326, 328, 16, 18);
    this.tower(187, 322, 26, 28);

    // Pijarska street and the blocks of the Old Town
    c.fillStyle = this.col($r('app.color.map_road'));
    c.fillRect(-10, 345, 410, 12);
    c.fillStyle = this.col($r('app.color.map_block'));
    c.fillRect(-10, 361, 56, h - 361);
    c.fillRect(56, 361, 132, 106);
    c.fillRect(56, 477, 132, h - 477);
    c.fillRect(214, 361, 108, 94);
    c.fillRect(214, 465, 108, h - 465);
    c.fillRect(332, 361, 68, h - 361);

    // street names
    c.fillStyle = this.col($r('app.color.map_label'));
    c.font = `9.5vp ${Fonts.MEDIUM}`;
    c.textAlign = 'left';
    c.textBaseline = 'alphabetic';
    c.fillText('Basztowa', 24, 151);
    c.fillText('Pijarska', 300, 354);
    c.fillStyle = this.col($r('app.color.map_label_park'));
    c.fillText('Planty', 20, 200);
    c.save();
    c.translate(205, 410);
    c.rotate(Math.PI / 2);
    c.fillStyle = this.col($r('app.color.map_label'));
    c.fillText('Floriańska', 0, 0);
    c.restore();
    c.fillStyle = this.col($r('app.color.map_label_place'));
    c.font = `11vp ${Fonts.SEMIBOLD}`;
    c.fillText('Barbakan', 232, 205);

    // walked part of the route, then the part ahead
    this.line([[200, 236], [200, 262]], this.col($r('app.color.map_road')), 10);
    this.line([[200, 236], [200, 262]], this.col($r('app.color.accent_soft')), 5);
    this.line([[200, 262], [200, 350], [202, h + 10]], this.col($r('app.color.map_road')), 11);
    this.line([[200, 262], [200, 350], [202, h + 10]], this.col($r('app.color.accent')), 6);

    // visited stop: Barbakan, with a tick
    this.circle(200, 216, 11, this.col($r('app.color.accent_soft')), this.col($r('app.color.map_road')), 2.5);
    c.strokeStyle = this.col($r('app.color.map_road'));
    c.lineWidth = 2;
    c.lineCap = 'round';
    c.lineJoin = 'round';
    c.beginPath();
    c.moveTo(195, 216);
    c.lineTo(198.5, 219.5);
    c.lineTo(205, 212.5);
    c.stroke();

    // next stop marker
    this.circle(200, 336, 12, this.col($r('app.color.map_road')), this.col($r('app.color.accent')), 2.5);
    c.fillStyle = this.col($r('app.color.accent'));
    c.font = `11vp ${Fonts.BOLD}`;
    c.textAlign = 'center';
    c.textBaseline = 'middle';
    c.fillText(`${this.nextStopNum}`, 200, 336.5);

    // you are here, with the heading cone
    this.circle(200, 262, 26, this.col($r('app.color.accent'), 0.1), '', 0);
    c.fillStyle = this.col($r('app.color.accent'), 0.22);
    c.beginPath();
    c.moveTo(200, 262);
    c.lineTo(184, 302);
    c.arc(200, 262, 43.1, Math.atan2(40, -16), Math.atan2(40, 16), true);
    c.closePath();
    c.fill();
    this.circle(200, 262, 8, this.col($r('app.color.accent')), this.col($r('app.color.map_road')), 3);

    c.restore();
  }

  /** Colour token from resources as a Canvas colour string, optionally with extra opacity. */
  private col(res: Resource, alpha: number = 1): string {
    const argb = this.getUIContext().getHostContext()?.resourceManager.getColorSync(res.id) ?? 0xFF000000;
    const a = ((argb >>> 24) & 0xFF) / 255 * alpha;
    return `rgba(${(argb >>> 16) & 0xFF}, ${(argb >>> 8) & 0xFF}, ${argb & 0xFF}, ${a.toFixed(3)})`;
  }

  private circle(x: number, y: number, r: number, fill: string, stroke: string, width: number): void {
    const c = this.ctx;
    c.beginPath();
    c.arc(x, y, r, 0, Math.PI * 2);
    c.fillStyle = fill;
    c.fill();
    if (stroke.length > 0) {
      c.strokeStyle = stroke;
      c.lineWidth = width;
      c.stroke();
    }
  }

  private tower(x: number, y: number, w: number, h: number): void {
    const c = this.ctx;
    c.fillStyle = this.col($r('app.color.map_tower'));
    c.fillRect(x, y, w, h);
    c.strokeStyle = this.col($r('app.color.map_tower_stroke'));
    c.lineWidth = 1;
    c.strokeRect(x, y, w, h);
  }

  private line(points: number[][], color: string, width: number): void {
    const c = this.ctx;
    c.strokeStyle = color;
    c.lineWidth = width;
    c.lineCap = 'round';
    c.lineJoin = 'round';
    c.beginPath();
    c.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) {
      c.lineTo(points[i][0], points[i][1]);
    }
    c.stroke();
  }
}
