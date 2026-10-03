// "W drodze": navigation during the walk, after docs/design/w-drodze.html.
// UI only, on the mock route: the guide engine (WalkViewModel) and location (P1) are wired later.
import { NarratorPlayer } from '../audio/NarratorPlayer';
import { Fonts } from '../common/Fonts';
import { WalkMap } from '../components/walk/WalkMap';
import { ROYAL_ROUTE, Route, RouteStop } from '../model/Route';

const SHEET_HEIGHT: number = 336;

@Entry
@Component
struct WalkPage {
  private route: Route = ROYAL_ROUTE;
  private player: NarratorPlayer = new NarratorPlayer();
  private timer: number = -1;
  @State current: number = 0;          // index of the stop being narrated
  @State elapsed: number = 0;          // seconds of narration played (mock clock)
  @State playing: boolean = false;
  @State showMore: boolean = false;
  @StorageProp('topInset') topInset: number = 0;
  @StorageProp('bottomInset') bottomInset: number = 0;

  aboutToAppear(): void {
    this.play();
  }

  // leaving the walk (button or system back) stops the narration
  aboutToDisappear(): void {
    this.pause();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      WalkMap({ nextStopNum: this.nextStop()?.num ?? 0 })

      Column() {
        this.DirectionCard()
      }
      .width('100%')
      .position({ x: 0, y: 0 })

      Column() {
        Row() {
          Blank()
          // UI only: centring on the user's position comes with the location provider (P1)
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_my_location')).width(20).height(20)
          }
          .width($r('app.float.round_button_size'))
          .height($r('app.float.round_button_size'))
          .backgroundColor($r('app.color.surface'))
          .shadow({ radius: 4, color: $r('app.color.shadow_button'), offsetY: 1 })
          .accessibilityText($r('app.string.a11y_my_location'))
        }
        .width('100%')
        .padding({ right: 16, bottom: 16 })

        this.Sheet()
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.map_bg'))
    .bindSheet($$this.showMore, this.MoreSheet(), {
      height: SheetSize.MEDIUM,
      backgroundColor: $r('app.color.surface'),
      dragBar: true,
      showClose: false,
    })
  }

  @Builder
  DirectionCard() {
    Row({ space: 14 }) {
      Column() {
        Image($r('app.media.ic_arrow_up')).width(26).height(26)
      }
      .width(52)
      .height(52)
      .borderRadius(14)
      .backgroundColor($r('app.color.accent'))
      .justifyContent(FlexAlign.Center)

      Column({ space: 1 }) {
        Row({ space: 8 }) {
          Text(this.route.legLabel(this.current + 1))
            .fontSize($r('app.float.font_distance'))
            .fontFamily(Fonts.BOLD)
            .fontColor($r('app.color.text'))
          Text(this.nextStop()?.name ?? '')
            .fontSize($r('app.float.font_body'))
            .fontFamily(Fonts.MEDIUM)
            .fontColor($r('app.color.text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Bottom)
        Text(this.directionLine())
          .fontSize($r('app.float.font_small'))
          .fontFamily(Fonts.REGULAR)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
    .borderRadius(20)
    .backgroundColor($r('app.color.surface'))
    .shadow({ radius: 10, color: $r('app.color.shadow_card'), offsetY: 2 })
    .margin({ left: 12, right: 12, top: this.topInset + 8 })
    .visibility(this.nextStop() !== null ? Visibility.Visible : Visibility.Hidden)
  }

  @Builder
  Sheet() {
    Column() {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.handle'))
        .alignSelf(ItemAlign.Center)

      Row({ space: 12 }) {
        Image(this.stop().image)
          .width($r('app.float.thumb_size'))
          .height($r('app.float.thumb_size'))
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.placeholder'))
        Column({ space: 2 }) {
          Text(this.stop().name)
            .fontSize($r('app.float.font_place'))
            .fontFamily(Fonts.SEMIBOLD)
            .fontColor($r('app.color.text'))
          Text(`${this.clock(this.elapsed)} / ${this.clock(this.stop().audioSeconds)}`)
            .fontSize($r('app.float.font_small'))
            .fontFamily(Fonts.REGULAR)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Image(this.playing ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
            .width(this.playing ? 16 : 18)
            .height(this.playing ? 16 : 18)
        }
        .width($r('app.float.play_button_size'))
        .height($r('app.float.play_button_size'))
        .backgroundColor($r('app.color.accent'))
        .accessibilityText(this.playing ? $r('app.string.a11y_pause') : $r('app.string.a11y_play'))
        .onClick(() => this.playing ? this.pause() : this.play())
      }
      .width('100%')
      .margin({ top: 16 })

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height($r('app.float.progress_height'))
          .borderRadius(2)
          .backgroundColor($r('app.color.progress_track'))
        Row()
          .width(`${Math.round(this.progress() * 100)}%`)
          .height($r('app.float.progress_height'))
          .borderRadius(2)
          .backgroundColor($r('app.color.accent'))
      }
      .width('100%')
      .margin({ top: 14 })

      // transcript: sentences already read are greyed out
      Text() {
        ForEach(this.stop().transcript, (sentence: string, i: number) => {
          Span(i < this.stop().transcript.length - 1 ? `${sentence} ` : sentence)
            .fontColor(i < this.sentencesRead() ? $r('app.color.text_muted') : $r('app.color.text'))
        }, (sentence: string, i: number) => `${this.current}-${i}-${i < this.sentencesRead()}`)
      }
      .fontSize($r('app.float.font_body'))
      .fontFamily(Fonts.REGULAR)
      .lineHeight(22)
      .width('100%')
      .margin({ top: 14 })

      Row({ space: 10 }) {
        Button($r('app.string.more_about_place'))
          .layoutWeight(1)
          .height($r('app.float.button_secondary_height'))
          .fontSize($r('app.float.font_label'))
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.accent_bg'))
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.showMore = true;
          })
        Button($r('app.string.skip'))
          .layoutWeight(1)
          .height($r('app.float.button_secondary_height'))
          .fontSize($r('app.float.font_label'))
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.text'))
          .backgroundColor($r('app.color.surface_muted'))
          .padding({ left: 8, right: 8 })
          .enabled(this.nextStop() !== null)
          .onClick(() => this.skip())
      }
      .width('100%')
      .margin({ top: 16 })

      Blank()

      Row() {
        Text(this.thenLine())
          .fontSize($r('app.float.font_small'))
          .fontFamily(Fonts.REGULAR)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Button($r('app.string.finish'))
          .height($r('app.float.touch_min'))
          .padding({ left: 2, right: 2 })
          .fontSize($r('app.float.font_label'))
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.danger'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.pause();
            this.getUIContext().getRouter().back();
          })
      }
      .width('100%')
    }
    .width('100%')
    .height(SHEET_HEIGHT + this.bottomInset)
    .padding({ left: 20, right: 20, top: 8, bottom: 8 + this.bottomInset })
    .borderRadius({ topLeft: $r('app.float.sheet_radius_large'), topRight: $r('app.float.sheet_radius_large') })
    .backgroundColor($r('app.color.surface'))
    .shadow({ radius: 12, color: $r('app.color.shadow_sheet'), offsetY: -2 })
  }

  @Builder
  MoreSheet() {
    Column({ space: 8 }) {
      Text(this.stop().name)
        .fontSize($r('app.float.font_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
      Text($r('app.string.source_wikipedia'))
        .fontSize($r('app.float.font_caption'))
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
      Text(this.stop().summary)
        .fontSize($r('app.float.font_body'))
        .fontFamily(Fonts.REGULAR)
        .lineHeight(22)
        .fontColor($r('app.color.text'))
        .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(20)
  }

  // ---- mock playback: the real narration comes from the guide engine ----

  private play(): void {
    if (this.elapsed >= this.stop().audioSeconds) {
      this.elapsed = 0;
    }
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      this.player.playRawFile(ctx, 'test.mp3');
    }
    this.playing = true;
    clearInterval(this.timer);
    this.timer = setInterval(() => {
      this.elapsed = Math.min(this.stop().audioSeconds, this.elapsed + 1);
      if (this.elapsed >= this.stop().audioSeconds) {
        this.pause();
      }
    }, 1000);
  }

  private pause(): void {
    clearInterval(this.timer);
    this.timer = -1;
    this.player.release();
    this.playing = false;
  }

  private skip(): void {
    if (this.nextStop() === null) {
      return;
    }
    this.pause();
    this.current++;
    this.elapsed = 0;
    this.play();
  }

  // ---- view helpers ----

  private stop(): RouteStop {
    return this.route.stops[this.current];
  }

  private nextStop(): RouteStop | null {
    return this.current + 1 < this.route.stops.length ? this.route.stops[this.current + 1] : null;
  }

  private progress(): number {
    return this.stop().audioSeconds > 0 ? this.elapsed / this.stop().audioSeconds : 0;
  }

  /** Sentences already read, assuming each takes time in proportion to its length. */
  private sentencesRead(): number {
    const sentences = this.stop().transcript;
    const total = sentences.reduce((sum: number, t: string) => sum + t.length, 0);
    let read = 0;
    let acc = 0;
    for (const t of sentences) {
      acc += t.length;
      if (total > 0 && acc / total <= this.progress()) {
        read++;
      }
    }
    return read;
  }

  private directionLine(): string {
    const next = this.nextStop();
    const ctx = this.getUIContext().getHostContext();
    if (next === null || ctx === undefined) {
      return '';
    }
    const stopOf = ctx.resourceManager.getStringSync($r('app.string.stop_of').id, next.num, this.route.stops.length);
    return `${next.approach} · ${stopOf}`;
  }

  private thenLine(): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    const after = this.current + 2;
    if (after >= this.route.stops.length) {
      return ctx.resourceManager.getStringSync($r('app.string.last_stop').id);
    }
    return ctx.resourceManager.getStringSync($r('app.string.then').id, this.route.stops[after].name,
      this.route.legLabel(after));
  }

  private clock(seconds: number): string {
    const s = Math.round(seconds);
    return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`;
  }
}
