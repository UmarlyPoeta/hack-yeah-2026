import { Route } from '../../model/Route';

@Component
export struct SavedView {
  routes: Route[] = [];

  build() {
    Column().width('100%').height('100%').backgroundColor($r('app.color.surface'))
  }
}
