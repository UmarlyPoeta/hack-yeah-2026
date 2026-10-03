import { Fonts, Palette } from '../common/Theme';

/** Compass card: where the next stop is relative to the walking direction (0° = straight ahead). */
@Component
export struct Radar {
  @Prop poiName: string = 'Najbliższy obiekt';
  @Prop distanceM: number = 120;
  @Prop @Watch('settle') bearingAngle: number = 45;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  // needle angle actually drawn; it springs towards bearingAngle like a real compass needle
  private shown: number = -60;
  private velocity: number = 0;
  private timer: number = -1;

  build() {
    Column() {
      Canvas(this.ctx)
        .width(96)
        .height(96)
        .onReady(() => this.settle())
      Text(this.directionText())
        .fontFamily(Fonts.ITALIC)
        .fontSize(14)
        .fontColor(Palette.INK_SOFT)
        .margin({ top: 6 })
    }
  }

  private directionText(): string {
    const a = ((this.bearingAngle % 360) + 360) % 360;
    if (a < 25 || a > 335) {
      return 'na wprost';
    }
    if (a >= 155 && a <= 205) {
      return 'za tobą';
    }
    return a < 180 ? 'po prawej' : 'po lewej';
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  settle(): void {
    clearInterval(this.timer);
    this.timer = setInterval(() => this.step(), 16);
  }

  private step(): void {
    // shortest way round, then a lightly damped spring
    let diff = ((this.bearingAngle - this.shown) % 360 + 540) % 360 - 180;
    this.velocity = this.velocity * 0.86 + diff * 0.018;
    this.shown += this.velocity;
    diff = ((this.bearingAngle - this.shown) % 360 + 540) % 360 - 180;
    if (Math.abs(diff) < 0.05 && Math.abs(this.velocity) < 0.05) {
      this.shown = this.bearingAngle;
      clearInterval(this.timer);
    }
    this.redraw();
  }

  redraw(): void {
    const c = this.ctx;
    const w = c.width;
    const h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    const cx = w / 2;
    const cy = h / 2;
    const r = Math.min(w, h) / 2 - 3;
    c.clearRect(0, 0, w, h);

    c.beginPath();
    c.arc(cx, cy, r, 0, Math.PI * 2);
    c.lineWidth = 1;
    c.strokeStyle = Palette.RULE;
    c.stroke();

    for (let i = 0; i < 24; i++) {
      const t = i * Math.PI / 12;
      const major = i % 6 === 0;
      const r1 = r - (major ? 9 : 5);
      c.beginPath();
      c.moveTo(cx + Math.sin(t) * r1, cy - Math.cos(t) * r1);
      c.lineTo(cx + Math.sin(t) * r, cy - Math.cos(t) * r);
      c.lineWidth = major ? 1.5 : 0.75;
      c.strokeStyle = major ? Palette.INK_SOFT : Palette.INK_FAINT;
      c.stroke();
    }

    // needle towards the stop
    const a = this.shown * Math.PI / 180;
    const tip = r - 13;
    const tail = r * 0.35;
    const side = 6;
    c.beginPath();
    c.moveTo(cx + Math.sin(a) * tip, cy - Math.cos(a) * tip);
    c.lineTo(cx + Math.cos(a) * side, cy + Math.sin(a) * side);
    c.lineTo(cx - Math.sin(a) * tail, cy + Math.cos(a) * tail);
    c.lineTo(cx - Math.cos(a) * side, cy - Math.sin(a) * side);
    c.closePath();
    c.fillStyle = Palette.BRICK;
    c.fill();

    c.beginPath();
    c.arc(cx, cy, 3, 0, Math.PI * 2);
    c.fillStyle = Palette.PAPER;
    c.fill();
  }
}
