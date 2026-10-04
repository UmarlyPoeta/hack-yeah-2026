// App shell: bottom bar with three tabs (Odkrywaj, Mapa, Zapisane).
// While the app is open, the landmark queue is refreshed from the user's position every few minutes.
import { Fonts, registerFonts } from '../common/Fonts';
import { DiscoverView } from '../components/discover/DiscoverView';
import { MapView } from '../components/map/MapView';
import { SavedView } from '../components/saved/SavedView';
import { Place } from '../model/Place';
import { PlaceQueue } from '../store/PlaceQueue';
import { UserLocation } from '../store/UserLocation';
import { setStatusBarLight } from '../common/StatusBar';

const TAB_DISCOVER: number = 0;
const TAB_MAP: number = 1;
const TAB_SAVED: number = 2;
const REFRESH_INTERVAL_MS: number = 120000;

@Entry
@Component
struct MainPage {
  @State tab: number = TAB_DISCOVER;
  @StorageProp('bottomInset') bottomInset: number = 0;
  private tabs: TabsController = new TabsController();
  private timer: number = -1;

  aboutToAppear(): void {
    registerFonts(this.getUIContext());
  }

  // back from a place (or from the background): one landmark may have left the queue, so fill it up
  onPageShow(): void {
    setStatusBarLight(this.getUIContext().getHostContext(), this.tab !== TAB_SAVED);
    this.refresh();
    clearInterval(this.timer);
    this.timer = setInterval(() => this.refresh(), REFRESH_INTERVAL_MS);
  }

  onPageHide(): void {
    clearInterval(this.timer);
    this.timer = -1;
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.tab, controller: this.tabs }) {
      TabContent() {
        DiscoverView({ onOpen: (place: Place) => this.open(place) })
      }
      .tabBar(this.TabItem(TAB_DISCOVER, $r('app.string.tab_discover'), $r('app.media.ic_tab_discover_on'),
        $r('app.media.ic_tab_discover_off')))

      TabContent() {
        MapView({ onOpen: (place: Place) => this.open(place) })
      }
      .tabBar(this.TabItem(TAB_MAP, $r('app.string.tab_map'), $r('app.media.ic_tab_map_on'),
        $r('app.media.ic_tab_map_off')))

      TabContent() {
        SavedView({ onOpen: (place: Place) => this.open(place) })
      }
      .tabBar(this.TabItem(TAB_SAVED, $r('app.string.tab_saved'), $r('app.media.ic_tab_saved_on'),
        $r('app.media.ic_tab_saved_off')))
    }
    .scrollable(false)
    .animationDuration(0)
    .barHeight(Math.max(64, 50 + this.bottomInset))
    .barBackgroundColor($r('app.color.surface'))
    .divider({ strokeWidth: 1, color: $r('app.color.separator') })
    .onChange((index: number) => {
      this.tab = index;
      // photo (Odkrywaj) and dark map: white icons; white "Zapisane": dark icons
      setStatusBarLight(this.getUIContext().getHostContext(), index !== TAB_SAVED);
    })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  TabItem(index: number, label: Resource, iconOn: Resource, iconOff: Resource) {
    Column({ space: 4 }) {
      Image(this.tab === index ? iconOn : iconOff).width(22).height(22)
      Text(label)
        .fontSize($r('app.float.font_tab'))
        .fontFamily(this.tab === index ? Fonts.BOLD : Fonts.SEMIBOLD)
        .fontColor(this.tab === index ? $r('app.color.accent') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: this.bottomInset })
  }

  private open(place: Place): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PlacePage', params: { place: place } });
  }

  private async refresh(): Promise<void> {
    const fix = (await UserLocation.current()) ?? UserLocation.known();
    if (fix !== null) {
      await PlaceQueue.refill(fix);
    }
  }
}
