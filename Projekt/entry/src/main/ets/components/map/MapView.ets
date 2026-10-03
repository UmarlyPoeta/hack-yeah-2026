import { Route } from '../../model/Route';

@Component
export struct MapView {
  route: Route | null = null;

  build() {
    Column().width('100%').height('100%').backgroundColor($r('app.color.map_bg'))
  }
}
