// Shown while the photos and the narration are on their way: the "tour" wordmark and a random
// fact (resources/base/element/strarray.json: tour_facts), changing every few seconds.
import { Fonts } from '../../common/Fonts';
import { Logo } from '../common/Controls';

const FACT_INTERVAL_MS: number = 7000;

@Component
export struct LoadingView {
  placeName: string = '';
  @State private facts: string[] = [];
  @State private index: number = 0;
  @State private factOpacity: number = 1;
  @State private barOffset: number = -1;   // indeterminate bar position, -1..1 of the track width
  @StorageProp('topInset') topInset: number = 0;
  @StorageProp('bottomInset') bottomInset: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      this.facts = ctx.resourceManager.getStringArrayValueSync($r('app.strarray.tour_facts').id);
    }
    this.index = this.facts.length > 0 ? Math.floor(Math.random() * this.facts.length) : 0;
    this.timer = setInterval(() => this.nextFact(), FACT_INTERVAL_MS);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  build() {
    Column() {
      Logo($r('app.float.font_title'), $r('app.color.on_ink'))

      Blank()

      Column({ space: 14 }) {
        Text($r('app.string.loading_fact'))
          .fontSize($r('app.float.font_caption'))
          .fontFamily(Fonts.BOLD)
          .fontColor($r('app.color.accent_bright'))
          .letterSpacing(1.5)
          .textCase(TextCase.UpperCase)
        Text(this.facts.length > 0 ? this.facts[this.index] : '')
          .fontSize($r('app.float.font_fact'))
          .lineHeight(30)
          .fontFamily(Fonts.SEMIBOLD)
          .fontColor($r('app.color.on_ink'))
          .opacity(this.factOpacity)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 12 })
      .border({ width: { left: 2 }, color: { left: $r('app.color.accent_bright') } })

      Blank()

      Column({ space: 10 }) {
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(2).backgroundColor($r('app.color.ink_line'))
          Row()
            .width('35%')
            .height(2)
            .backgroundColor($r('app.color.accent_bright'))
            .translate({ x: `${Math.round(this.barOffset * 100)}%` })
        }
        .width('100%')
        .clip(true)
        .onAppear(() => {
          this.getUIContext().animateTo({ duration: 1400, iterations: -1, curve: Curve.EaseInOut }, () => {
            this.barOffset = 2;
          });
        })
        Text(`${this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.loading_wait').id) ?? ''} · ${this.placeName}`)
          .fontSize($r('app.float.font_small'))
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.on_ink_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24, top: this.topInset + 20, bottom: this.bottomInset + 28 })
    .backgroundColor($r('app.color.ink'))
  }

  private nextFact(): void {
    if (this.facts.length < 2) {
      return;
    }
    this.getUIContext().animateTo({ duration: 250 }, () => {
      this.factOpacity = 0;
    });
    setTimeout(() => {
      this.index = (this.index + 1) % this.facts.length;
      this.getUIContext().animateTo({ duration: 350 }, () => {
        this.factOpacity = 1;
      });
    }, 260);
  }
}
