// App shell: bottom bar with three tabs (Odkrywaj, Mapa, Zapisane), after docs/design/start.html.
import { Fonts, registerFonts } from '../common/Fonts';
import { DiscoverView } from '../components/discover/DiscoverView';
import { MapView } from '../components/map/MapView';
import { SavedView } from '../components/saved/SavedView';
import { ROYAL_ROUTE, SAVED_ROUTES } from '../model/Route';

const TAB_DISCOVER: number = 0;
const TAB_MAP: number = 1;
const TAB_SAVED: number = 2;

@Entry
@Component
struct MainPage {
  @State tab: number = TAB_DISCOVER;
  @StorageProp('bottomInset') bottomInset: number = 0;
  private tabs: TabsController = new TabsController();

  aboutToAppear(): void {
    registerFonts(this.getUIContext());
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.tab, controller: this.tabs }) {
      TabContent() {
        DiscoverView({
          route: ROYAL_ROUTE,
          onStart: () => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/WalkPage' });
          },
          onShowMap: () => {
            this.tabs.changeIndex(TAB_MAP);
          }
        })
      }
      .tabBar(this.TabItem(TAB_DISCOVER, $r('app.string.tab_discover'), $r('app.media.ic_tab_discover_on'),
        $r('app.media.ic_tab_discover_off')))

      TabContent() {
        MapView({ route: ROYAL_ROUTE })
      }
      .tabBar(this.TabItem(TAB_MAP, $r('app.string.tab_map'), $r('app.media.ic_tab_map_on'),
        $r('app.media.ic_tab_map_off')))

      TabContent() {
        SavedView({ routes: SAVED_ROUTES })
      }
      .tabBar(this.TabItem(TAB_SAVED, $r('app.string.tab_saved'), $r('app.media.ic_tab_saved_on'),
        $r('app.media.ic_tab_saved_off')))
    }
    .scrollable(false)
    .animationDuration(0)
    .barHeight(Math.max(64, 50 + this.bottomInset))   // design: 78 vp incl. the bottom inset
    .barBackgroundColor($r('app.color.surface'))
    .divider({ strokeWidth: 1, color: $r('app.color.separator') })
    .onChange((index: number) => {
      this.tab = index;
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
}
