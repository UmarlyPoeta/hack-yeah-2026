// "Mapa" tab: dark Leaflet map (rawfile/map/index.html in ArkWeb) with the queued and saved landmarks.
// Tapping a dot selects the landmark: its name shows next to the dot and a card opens at the bottom.
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Fonts } from '../../common/Fonts';
import { distanceM } from '../../guide/geo';
import { distanceLabel, Place, placeImage, shortName } from '../../model/Place';
import { PrimaryButton } from '../common/Controls';

interface MapPlace {
  id: string;
  name: string;
  lat: number;
  lon: number;
}

/** Object injected into the page as window.tourBridge. */
class MapBridge {
  onSelectId: (id: string) => void = () => {};

  onSelect(id: string): void {
    this.onSelectId(id);
  }
}

@Component
export struct MapView {
  onOpen: (place: Place) => void = () => {};
  @StorageLink('queue') @Watch('pushPlaces') queue: Place[] = [];
  @StorageLink('saved') @Watch('pushPlaces') saved: Place[] = [];
  @StorageProp('userLat') @Watch('pushUser') userLat: number = 0;
  @StorageProp('userLon') userLon: number = 0;
  @StorageProp('topInset') topInset: number = 0;
  @State selectedId: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: MapBridge = new MapBridge();
  private ready: boolean = false;

  aboutToAppear(): void {
    this.bridge.onSelectId = (id: string) => {
      this.selectedId = id;
    };
    // the landmark on the "Odkrywaj" photo is the one selected at first
    this.selectedId = this.queue.length > 0 ? this.queue[0].id : '';
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Web({ src: $rawfile('map/index.html'), controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .backgroundColor($r('app.color.ink'))
        .javaScriptProxy({
          object: this.bridge,
          name: 'tourBridge',
          methodList: ['onSelect'],
          controller: this.controller,
        })
        .onConsole((event) => {
          hilog.info(0x0000, 'MapWeb', '%{public}s', event?.message.getMessage() ?? '');
          return false;
        })
        .onPageEnd(() => {
          this.ready = true;
          this.pushUser();
          this.pushPlaces();
        })

      Row() {
        Text($r('app.string.map_title'))
          .fontSize($r('app.float.font_title'))
          .fontFamily(Fonts.EXTRABOLD)
          .fontColor($r('app.color.on_ink'))
        Blank()
        Text(this.countLabel())
          .fontSize($r('app.float.font_small'))
          .fontFamily(Fonts.SEMIBOLD)
          .fontColor($r('app.color.on_ink_secondary'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topInset + 12, bottom: 14 })
      .backgroundColor($r('app.color.ink'))
      .border({ width: { bottom: 1 }, color: { bottom: $r('app.color.ink_line') } })
      .position({ x: 0, y: 0 })

      Column({ space: 12 }) {
        Row() {
          Blank()
          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.ic_my_location_light')).width(20).height(20)
          }
          .width($r('app.float.square_button_size'))
          .height($r('app.float.square_button_size'))
          .borderRadius($r('app.float.radius'))
          .backgroundColor($r('app.color.ink_raised'))
          .border({ width: 1, color: $r('app.color.ink_line'), radius: $r('app.float.radius') })
          .accessibilityText($r('app.string.a11y_my_location'))
          .onClick(() => this.run('window.tour.centerOnUser()'))
        }
        .width('100%')

        if (this.selected() !== null) {
          this.SelectedCard(this.selected() as Place)
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ink'))
  }

  @Builder
  SelectedCard(place: Place) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Image(placeImage(place))
          .width($r('app.float.thumb_size'))
          .height($r('app.float.thumb_size'))
          .objectFit(ImageFit.Cover)
          .borderRadius($r('app.float.radius'))
          .backgroundColor($r('app.color.ink_line'))
        Column({ space: 4 }) {
          Text(shortName(place))
            .fontSize($r('app.float.font_place'))
            .fontFamily(Fonts.BOLD)
            .fontColor($r('app.color.on_ink'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.distance(place))
            .fontSize($r('app.float.font_small'))
            .fontFamily(Fonts.MEDIUM)
            .fontColor($r('app.color.on_ink_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      PrimaryButton($r('app.string.listen'), false, () => this.onOpen(place))
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.ink_raised'))
    .border({ width: { left: 2 }, color: { left: $r('app.color.accent_bright') } })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 24 })).animation({ duration: 200 }))
  }

  private all(): Place[] {
    const out: Place[] = this.queue.slice();
    for (const p of this.saved) {
      if (!out.some((q: Place) => q.id === p.id)) {
        out.push(p);
      }
    }
    return out;
  }

  private selected(): Place | null {
    return this.all().find((p: Place) => p.id === this.selectedId) ?? null;
  }

  pushPlaces(): void {
    const places: MapPlace[] = this.all().map((p: Place) => {
      const m: MapPlace = { id: p.id, name: shortName(p), lat: p.lat, lon: p.lon };
      return m;
    });
    this.run(`window.tour.setPlaces(${JSON.stringify(places)}, ${JSON.stringify(this.selectedId)})`);
  }

  pushUser(): void {
    if (this.userLat !== 0 || this.userLon !== 0) {
      this.run(`window.tour.setUser(${this.userLat}, ${this.userLon})`);
    }
  }

  private run(script: string): void {
    if (!this.ready) {
      return;
    }
    this.controller.runJavaScript(script).catch(() => {
      // the page is reloading; onPageEnd pushes everything again
    });
  }

  private distance(place: Place): string {
    if (this.userLat === 0 && this.userLon === 0) {
      return '';
    }
    const ctx = this.getUIContext().getHostContext();
    const d = distanceLabel(distanceM({ lat: this.userLat, lon: this.userLon }, place));
    return ctx === undefined ? d : ctx.resourceManager.getStringSync($r('app.string.from_you').id, d);
  }

  private countLabel(): string {
    const ctx = this.getUIContext().getHostContext();
    return ctx === undefined ? '' : ctx.resourceManager.getStringSync($r('app.string.map_nearby').id, this.queue.length);
  }
}
