import { NarratorPlayer } from '../audio/NarratorPlayer';
import { Teleprompter } from '../components/Teleprompter';
import { RouteStrip } from '../components/RouteStrip';
import { Radar } from '../components/Radar';
import { SessionBadge } from '../components/SessionBadge';
import { DeepDiveSheet } from '../components/DeepDiveSheet';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';
import { Eyebrow, Fonts, Motion, Palette } from '../common/Theme';

// Importy dla lokalizacji i uprawnień
import geoLocationManager from '@ohos.geoLocationManager';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { BusinessError } from '@ohos.base';

@Entry
@Component
struct WalkPage {
  @State private entered: boolean = false;
  private player: NarratorPlayer = new NarratorPlayer();

  @State currentText: string =
    'Zaczynamy spacer. Pierwszy przystanek: Barbakan w Krakowie, ok. 120 m przed nami.';

  @State poiName: string = 'Barbakan w Krakowie';
  @State segmentKind: string = 'WELCOME';
  @State nextPoiName: string = 'Brama Floriańska';
  @State distanceM: number = 120;
  @State etaSeconds: number = 90;
  @State sessionState: string = 'IDLE';
  @State bearingAngle: number = 45;
  @State isDeepDiveOpen: boolean = false;

  @State currentLat: number = 0;
  @State currentLng: number = 0;

  @State laterStops: string[] = ['Kościół Mariacki', 'Sukiennice', 'Collegium Maius', 'Wawel'];

  startLocationUpdates() {
    this.sessionState = 'ACQUIRING';
    const requestInfo: geoLocationManager.LocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
      timeInterval: 1,
      distanceInterval: 0
    };

    try {
      geoLocationManager.on('locationChange', requestInfo, (location: geoLocationManager.Location) => {
        this.sessionState = 'WALKING';
        this.currentLat = location.latitude;
        this.currentLng = location.longitude;
      });
    } catch (err) {
      const error = err as BusinessError;
      this.sessionState = 'ERROR';
      console.error(`Błąd lokalizacji: ${error.message}`);
    }
  }

  aboutToDisappear(): void {
    this.player.release();
    try {
      geoLocationManager.off('locationChange');
    } catch (_err) {
      // Ignoruj błąd wyłączenia
    }
  }

  pageTransition() {
    PageTransitionEnter({ duration: 420, curve: Motion.EASE_OUT })
      .opacity(0)
      .translate({ y: 24 })
    PageTransitionExit({ duration: 220, curve: Curve.EaseIn })
      .opacity(0)
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Eyebrow('SPACER · KRAKÓW')
          Blank()
          SessionBadge({ sessionState: this.sessionState })
        }
        .width('100%')
        .margin({ top: 8 })
        .opacity(this.entered ? 1 : 0)
        .translate({ y: this.entered ? 0 : Motion.ENTER_SHIFT })
        .animation({ duration: Motion.ENTER_MS, curve: Motion.EASE_OUT, delay: 0 })

        // Przycisk startowy, gdy spacer jest nieaktywny
        if (this.sessionState === 'IDLE' || this.sessionState === 'PAUSED' || this.sessionState === 'ERROR') {
          Button('Rozpocznij spacer (Autoryzuj GPS)')
            .width('100%')
            .height(44)
            .backgroundColor(Palette.INK)
            .fontColor(Palette.PAPER)
            .borderRadius(12)
            .margin({ top: 12 })
            .onClick(() => {
              const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
              const context = getContext(this) as common.UIAbilityContext;
              const permissions: Array<Permissions> = ['ohos.permission.APPROXIMATELY_LOCATION'];

              atManager.requestPermissionsFromUser(context, permissions)
                .then((data) => {
                  if (data.authResults.length > 0 && data.authResults[0] === 0) {
                    this.startLocationUpdates();
                  } else {
                    this.sessionState = 'ERROR';
                  }
                })
                .catch((_err: BusinessError) => {
                  this.sessionState = 'ERROR';
                });
            })
        } else {
          // Wyświetlanie aktualnych współrzędnych GPS na żywo
          Row() {
            Text(`📍 Szer: ${this.currentLat.toFixed(5)} | Dług: ${this.currentLng.toFixed(5)}`)
              .fontSize(13)
              .fontFamily(Fonts.ITALIC)
              .fontColor(Palette.INK_SOFT)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 12 })
        }

        Row() {
          RouteStrip({
            nextPoiName: this.nextPoiName,
            distanceM: this.distanceM,
            etaSeconds: this.etaSeconds
          })
            .layoutWeight(1)
          Radar({
            poiName: this.nextPoiName,
            distanceM: this.distanceM,
            bearingAngle: this.bearingAngle
          })
            .margin({ left: 16 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: 28 })
        .opacity(this.entered ? 1 : 0)
        .translate({ y: this.entered ? 0 : Motion.ENTER_SHIFT })
        .animation({ duration: Motion.ENTER_MS, curve: Motion.EASE_OUT, delay: 1 * Motion.STAGGER_MS })

        Column() {
          Eyebrow('DALEJ NA TRASIE')
          Text(this.laterStops.join('  ·  '))
            .fontFamily(Fonts.ITALIC)
            .fontSize(17)
            .lineHeight(25)
            .fontColor(Palette.INK_SOFT)
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 16 })
        .margin({ top: 22 })
        .border({ width: { top: 1 }, color: Palette.RULE })
        .opacity(this.entered ? 1 : 0)
        .translate({ y: this.entered ? 0 : Motion.ENTER_SHIFT })
        .animation({ duration: Motion.ENTER_MS, curve: Motion.EASE_OUT, delay: 2 * Motion.STAGGER_MS })

        Blank()

        Teleprompter({
          currentText: this.currentText,
          poiName: this.poiName,
          segmentKind: this.segmentKind,
          onPlayClick: () => {
            const context = getContext(this) as common.UIAbilityContext;
            this.player.playRawFile(context, 'test.mp3');
          }
        })
          .opacity(this.entered ? 1 : 0)
          .translate({ y: this.entered ? 0 : Motion.ENTER_SHIFT })
          .animation({ duration: Motion.ENTER_MS, curve: Motion.EASE_OUT, delay: 3 * Motion.STAGGER_MS })

        Button({ type: ButtonType.Normal }) {
          Row() {
            Text('Opowiedz więcej o tym miejscu')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.INK)
            Blank()
            Text('↑')
              .fontSize(17)
              .fontColor(Palette.INK)
          }
          .width('100%')
          .padding({ left: 20, right: 20 })
        }
        .width('100%')
        .height(52)
        .borderRadius(14)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: Palette.INK, radius: 14 })
        .margin({ top: 14 })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
        .opacity(this.entered ? 1 : 0)
        .translate({ y: this.entered ? 0 : Motion.ENTER_SHIFT })
        .animation({ duration: Motion.ENTER_MS, curve: Motion.EASE_OUT, delay: 4 * Motion.STAGGER_MS })
        .onClick(() => {
          this.isDeepDiveOpen = true;
        })

        Text('Zakończ spacer')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.BRICK)
          .padding(12)
          .margin({ top: 10, bottom: 8 })
          .onClick(() => {
            this.player.release();
            try {
              geoLocationManager.off('locationChange');
            } catch (_err) {}
            router.back();
          })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })
      .backgroundColor(Palette.PAPER)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAppear(() => {
        this.entered = true;
      })

      DeepDiveSheet({
        isShown: $isDeepDiveOpen,
        title: this.poiName,
        content: 'Barbakan (zwany też Rondlem) – barbakan, najbardziej wysunięta na północ część fortyfikacji ' +
          'miejskich Krakowa. Znajduje się na Plantach, przed Bramą Floriańską, po południowej stronie ul. Basztowej.'
      })
    }
    .width('100%')
    .height('100%')
  }
}