import { abilityAccessCtrl, common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { distributedDataObject } from '@kit.ArkData';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { liveViewManager } from '@kit.LiveViewKit';
import { geoLocationManager } from '@kit.LocationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { NarratorPlayer } from '../audio/NarratorPlayer';

// SPIKE (branch spike/super-device): checks on the emulator which HarmonyOS features the
// "phone + watch as one guide" plan can rely on. Each button calls the real API and logs the
// result or the error code. Not product code.

class SharedState {
  title: string = '';
  seq: number = 0;
}

function describe(e: Object): string {
  const err = e as BusinessError;
  return 'BŁĄD ' + err.code + ': ' + err.message;
}

@Entry
@Component
struct SpikePage {
  @State lines: string[] = [];
  @StorageProp('continuationData') continuationData: string = '';
  private session: avSession.AVSession | null = null;
  private player: NarratorPlayer = new NarratorPlayer();
  private liveViewId: number = 1;
  private dataObject: distributedDataObject.DataObject | null = null;

  aboutToAppear(): void {
    this.log('Urządzenie: ' + deviceInfo.deviceType + ' · API ' + deviceInfo.sdkApiVersion
      + ' · ' + deviceInfo.marketName);
    if (this.continuationData.length > 0) {
      this.log('KONTYNUACJA: otrzymano ' + this.continuationData);
    }
    if (deviceInfo.deviceType === 'wearable') {
      // the round screen shows only the first button: run every check in sequence instead
      setTimeout(() => this.runAll(), 1500);
    }
  }

  private async runAll(): Promise<void> {
    this.log('ZEGAREK: uruchamiam wszystkie testy po kolei');
    await this.startSession();
    await this.startBackground();
    await this.startLiveView();
    await this.distributed();
    await this.askLocation();
    await this.server();
    this.log('ZEGAREK: koniec testów');
  }

  aboutToDisappear(): void {
    this.player.release();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private log(line: string): void {
    const time = new Date().toTimeString().slice(0, 8);
    hilog.info(0x5350, 'SPIKE', '%{public}s', line);   // readable with: hdc hilog -T SPIKE
    this.lines = [time + '  ' + line].concat(this.lines).slice(0, 60);
  }

  private async agent(): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [{ bundleName: this.ctx().abilityInfo.bundleName, abilityName: 'EntryAbility' }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(info);
  }

  // --- 1. Location: LocationButton has no type declaration in the public HarmonyOS 6.1.1 SDK,
  // so this checks the runtime permission dialog instead (is there an "only this time" option?)
  private async askLocation(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const res = await atManager.requestPermissionsFromUser(this.ctx(),
        ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
      this.log('ZGODA NA LOKALIZACJĘ: ' + res.authResults.join(',') + ' (0 = przyznane)');
      if (res.authResults[0] === 0) {
        await this.readLocation();
      }
    } catch (e) {
      this.log('ZGODA ' + describe(e));
    }
  }

  private async readLocation(): Promise<void> {
    try {
      const req: geoLocationManager.SingleLocationRequest = {
        locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
        locatingTimeoutMs: 10000
      };
      const loc = await geoLocationManager.getCurrentLocation(req);
      this.log('LOKALIZACJA OK: ' + loc.latitude.toFixed(5) + ', ' + loc.longitude.toFixed(5)
        + ' ±' + Math.round(loc.accuracy) + ' m');
    } catch (e) {
      this.log('LOKALIZACJA ' + describe(e));
    }
  }

  // --- 2. AVSession + background audio
  private async startSession(): Promise<void> {
    if (this.session !== null) {
      this.log('AVSESSION już aktywna, gram ponownie');
      this.player.playRawFile(this.ctx(), 'test.mp3');
      return;
    }
    try {
      const s = await avSession.createAVSession(this.ctx(), 'SpacerZHistoria', 'audio');
      this.session = s;
      const meta: avSession.AVMetadata = {
        assetId: 'spike-1', title: 'Sukiennice', artist: 'Spacer z historią · Bielik', album: 'Kraków'
      };
      await s.setAVMetadata(meta);
      const state: avSession.AVPlaybackState = {
        state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
        position: { elapsedTime: 0, updateTime: Date.now() }
      };
      await s.setAVPlaybackState(state);
      s.on('play', () => this.log('AVSESSION komenda: play'));
      s.on('pause', () => this.log('AVSESSION komenda: pause'));
      s.on('playNext', () => this.log('AVSESSION komenda: next'));
      s.on('playPrevious', () => this.log('AVSESSION komenda: previous'));
      await s.activate();
      this.log('AVSESSION OK: aktywna. Sprawdź centrum sterowania (przeciągnij z prawego górnego rogu).');
      this.player.playRawFile(this.ctx(), 'test.mp3');
      this.log('Gram test.mp3');
    } catch (e) {
      this.log('AVSESSION ' + describe(e));
    }
  }

  private async startBackground(): Promise<void> {
    try {
      await backgroundTaskManager.startBackgroundRunning(this.ctx(),
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, await this.agent());
      this.log('ZADANIE W TLE OK (AUDIO_PLAYBACK). Zablokuj ekran: czy dźwięk gra dalej?');
    } catch (e) {
      this.log('ZADANIE W TLE ' + describe(e));
    }
  }

  private async stopSession(): Promise<void> {
    try {
      this.player.release();
      if (this.session !== null) {
        await this.session.destroy();
        this.session = null;
      }
      await backgroundTaskManager.stopBackgroundRunning(this.ctx());
      this.log('AVSESSION i zadanie w tle zatrzymane');
    } catch (e) {
      this.log('STOP ' + describe(e));
    }
  }

  // --- 3. Live View (navigation template)
  private async startLiveView(): Promise<void> {
    try {
      const enabled = await liveViewManager.isLiveViewEnabled();
      this.log('LIVE VIEW włączone w ustawieniach: ' + enabled);
      const lv: liveViewManager.LiveView = {
        id: this.liveViewId,
        event: 'NAVIGATION',
        liveViewData: {
          primary: {
            title: 'Sukiennice',
            content: [{ text: '120 m po prawej · 1:30' }],
            keepTime: 15,
            clickAction: await this.agent(),
            layoutData: {
              layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_NAVIGATION,
              currentNavigationIcon: 'spike_nav.png',     // file name in resources/rawfile
              navigationIcons: ['spike_nav.png']
            }
          }
        }
      };
      const r = await liveViewManager.startLiveView(lv);
      this.log('LIVE VIEW start: kod ' + r.resultCode + ' ' + r.message);
    } catch (e) {
      this.log('LIVE VIEW ' + describe(e));
    }
  }

  private async stopLiveView(): Promise<void> {
    try {
      const lv: liveViewManager.LiveView = {
        id: this.liveViewId, event: 'NAVIGATION',
        liveViewData: { primary: { title: 'Koniec spaceru', content: [{ text: 'Dziękujemy' }] } }
      };
      const r = await liveViewManager.stopLiveView(lv);
      this.log('LIVE VIEW stop: kod ' + r.resultCode);
    } catch (e) {
      this.log('LIVE VIEW stop ' + describe(e));
    }
  }

  // --- 4. Distributed: devices around + distributed data object
  private async distributed(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const res = await atManager.requestPermissionsFromUser(this.ctx(), ['ohos.permission.DISTRIBUTED_DATASYNC']);
      this.log('UPRAWNIENIE DISTRIBUTED_DATASYNC: ' + (res.authResults[0] === 0 ? 'przyznane' : 'odmowa'));
    } catch (e) {
      this.log('UPRAWNIENIE ' + describe(e));
    }
    try {
      const dm = distributedDeviceManager.createDeviceManager(this.ctx().abilityInfo.bundleName);
      const devices = dm.getAvailableDeviceListSync();
      this.log('URZĄDZENIA W POBLIŻU (zaufane): ' + devices.length + ' '
        + devices.map((d) => d.deviceName + '/' + d.deviceType).join(', '));
    } catch (e) {
      this.log('DEVICE MANAGER ' + describe(e));
    }
    try {
      const obj = distributedDataObject.create(this.ctx(), new SharedState());
      obj.on('change', (sessionId: string, fields: string[]) => {
        this.log('DATA OBJECT zmiana z innego urządzenia: ' + fields.join(','));
      });
      obj.on('status', (sessionId: string, networkId: string, status: string) => {
        this.log('DATA OBJECT status: ' + status + ' (' + networkId.slice(0, 8) + ')');
      });
      await obj.setSessionId('spacer_spike_0001');
      this.dataObject = obj;
      this.log('DATA OBJECT OK: sesja spacer_spike_0001 (na drugim urządzeniu ta sama sesja = synchronizacja)');
    } catch (e) {
      this.log('DATA OBJECT ' + describe(e));
    }
  }

  // --- 5. Can the emulator reach a server on the laptop? (plain HTTP, three addresses)
  private async server(): Promise<void> {
    const urls: string[] = ['http://10.0.2.2:8787/', 'http://192.168.18.100:8787/', 'http://127.0.0.1:8787/'];
    for (const url of urls) {
      const req = http.createHttp();
      try {
        const r = await req.request(url, { connectTimeout: 3000, readTimeout: 3000 });
        this.log('SERWER ' + url + ' → HTTP ' + r.responseCode);
      } catch (e) {
        this.log('SERWER ' + url + ' ' + describe(e));
      } finally {
        req.destroy();
      }
    }
  }

  build() {
    Column({ space: 8 }) {
      Text('SPIKE · Super Device / zegarek / AVSession / Live View').fontSize(13).fontWeight(FontWeight.Bold)
        .fontColor('#B35900')
      Scroll() {
        Column({ space: 8 }) {
          Text('1. Lokalizacja: LocationButton nie istnieje w publicznym SDK 6.1.1 (brak deklaracji); test zgody jednorazowej')
            .fontSize(13).fontWeight(FontWeight.Medium)
          Button('Poproś o lokalizację').fontSize(12).onClick(() => this.askLocation())
          Text('2. AVSession + dźwięk w tle').fontSize(13).fontWeight(FontWeight.Medium)
          Row({ space: 6 }) {
            Button('Sesja + gra').fontSize(12).onClick(() => this.startSession())
            Button('Tło').fontSize(12).onClick(() => this.startBackground())
            Button('Stop').fontSize(12).onClick(() => this.stopSession())
          }
          Text('3. Live View (nawigacja)').fontSize(13).fontWeight(FontWeight.Medium)
          Row({ space: 6 }) {
            Button('Start').fontSize(12).onClick(() => this.startLiveView())
            Button('Stop').fontSize(12).onClick(() => this.stopLiveView())
          }
          Text('4. Super Device: urządzenia + wspólny obiekt').fontSize(13).fontWeight(FontWeight.Medium)
          Button('Sprawdź').fontSize(12).onClick(() => this.distributed())
          Button('Serwer na laptopie').fontSize(12).onClick(() => this.server())
          Text('5. Kontynuacja: włączona w EntryAbility (onContinue); test tylko na 2 prawdziwych urządzeniach')
            .fontSize(11).fontColor('#5B6672')
          Divider()
          ForEach(this.lines, (l: string) => {
            Text(l).fontSize(11).width('100%')
          }, (l: string, i: number) => i + l)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1)
    }
    .padding(deviceInfo.deviceType === 'wearable' ? 24 : 12)
    .width('100%').height('100%')
  }
}
