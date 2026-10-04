// One landmark: photos from Wikipedia and the narration from the server (Bielik + TTS), started from
// "Posłuchaj historii". Both are fetched together; LoadingView stays until both are ready.
// Router params: { place: Place } (the whole place, so it opens even if the queue rotated meanwhile).
import { LengthMetrics } from '@kit.ArkUI';
import { NarratorPlayer, PlaybackListener } from '../audio/NarratorPlayer';
import { Fonts } from '../common/Fonts';
import { PhotoIconButton, PrimaryButton } from '../components/common/Controls';
import { LoadingView } from '../components/place/LoadingView';
import { splitSentences } from '../guide/Templates';
import { Place, placeImage, shortName } from '../model/Place';
import { Segment, SegmentKind, SegmentOrigin } from '../model/Segment';
import { fetchText } from '../store/LocalFiles';
import { PlaceQueue } from '../store/PlaceQueue';
import { SavedPlaces } from '../store/SavedPlaces';
import { NARRATION_TIMEOUT_MS, Services } from '../store/Services';
import { setStatusBarLight } from '../common/StatusBar';
import { Settings } from '../store/Settings';

const MAX_PHOTOS: number = 5;
const NARRATION_WORDS: number = 90;

interface PlaceParams {
  place?: Place;
}

interface MediaSrc {
  src: string;
}

interface MediaItem {
  type: string;
  title: string;
  showInGallery: boolean;
  srcset?: MediaSrc[];
}

interface MediaList {
  items: MediaItem[];
}

@Entry
@Component
struct PlacePage {
  @State place: Place | null = null;
  @State loading: boolean = true;
  @State photos: string[] = [];
  @State photoIndex: number = 0;
  @State segment: Segment | null = null;
  @State sentences: string[] = [];
  @State playing: boolean = false;
  @State positionMs: number = 0;
  @State durationMs: number = 0;
  @State showMore: boolean = false;
  @StorageLink('saved') saved: Place[] = [];
  @StorageProp('topInset') topInset: number = 0;
  @StorageProp('bottomInset') bottomInset: number = 0;
  private player: NarratorPlayer = new NarratorPlayer();
  private started: boolean = false;

  aboutToAppear(): void {
    setStatusBarLight(this.getUIContext().getHostContext(), true);
    const params = this.getUIContext().getRouter().getParams() as PlaceParams;
    this.place = params?.place ?? null;
    if (this.place !== null) {
      this.load(this.place);
    } else {
      setTimeout(() => this.getUIContext().getRouter().back(), 0);
    }
  }

  // leaving the place (back button or system back) stops the narration
  aboutToDisappear(): void {
    this.player.release();
    setStatusBarLight(this.getUIContext().getHostContext(), true);   // back to the photo on "Odkrywaj"
    if (this.place !== null && !this.loading) {
      PlaceQueue.visited(this.place.id);
    }
  }

  build() {
    Stack() {
      if (this.place !== null) {
        if (this.loading) {
          LoadingView({ placeName: shortName(this.place) })
            .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
        } else {
          this.Content(this.place)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.loading ? $r('app.color.ink') : $r('app.color.surface'))
    .bindSheet($$this.showMore, this.MoreSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: $r('app.color.surface'),
      dragBar: true,
      showClose: false,
      radius: LengthMetrics.vp(2),
    })
  }

  @Builder
  Content(place: Place) {
    Column() {
      Scroll() {
        Column() {
          this.Gallery(place)
          this.Narration(place)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
      .layoutWeight(1)

      // pinned to the bottom of the screen
      Column() {
        PrimaryButton($r('app.string.more_about_place'), true, () => {
          this.showMore = true;
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 + this.bottomInset })
      .backgroundColor($r('app.color.surface'))
      .border({ width: { top: 1 }, color: { top: $r('app.color.separator') } })
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 400 }))
  }

  @Builder
  Gallery(place: Place) {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper() {
        ForEach(this.photos, (src: string) => {
          Image(src)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.placeholder'))
            .accessibilityText(place.name)
        }, (src: string) => src)
      }
      .width('100%')
      .height('100%')
      .indicator(false)
      .loop(false)
      .onChange((i: number) => {
        this.photoIndex = i;
      })

      // status bar scrim
      Column()
        .width('100%')
        .height(this.topInset + 72)
        .linearGradient({ direction: GradientDirection.Bottom, colors: [[$r('app.color.photo_chip_bg'), 0], ['#00000000', 1]] })
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.Transparent)

      Row() {
        PhotoIconButton($r('app.media.ic_back_light'), $r('app.string.a11y_back'), () => {
          this.getUIContext().getRouter().back();
        })
        Blank()
        PhotoIconButton(this.isSaved(place.id) ? $r('app.media.ic_bookmark_light_on') : $r('app.media.ic_bookmark_light'),
          this.isSaved(place.id) ? $r('app.string.a11y_unsave') : $r('app.string.a11y_save'),
          () => SavedPlaces.toggle(place))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .position({ x: 0, y: this.topInset + 8 })

      if (this.photos.length > 1) {
        // square page markers
        Row({ space: 4 }) {
          ForEach(this.photos, (src: string, i: number) => {
            Row()
              .width(i === this.photoIndex ? 18 : 6)
              .height(3)
              .backgroundColor(i === this.photoIndex ? $r('app.color.on_primary') : $r('app.color.photo_button_bg'))
              .animation({ duration: 200 })
          }, (src: string) => src)
        }
        .margin({ bottom: 14 })
      }
    }
    .width('100%')
    .height($r('app.float.gallery_height'))
  }

  @Builder
  Narration(place: Place) {
    Column() {
      Text(shortName(place))
        .fontSize($r('app.float.font_hero_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
        .letterSpacing(-0.6)
      Text(this.originLabel())
        .fontSize($r('app.float.font_caption'))
        .fontFamily(Fonts.BOLD)
        .fontColor($r('app.color.accent'))
        .letterSpacing(1)
        .textCase(TextCase.UpperCase)
        .margin({ top: 6 })

      if (this.hasAudio()) {
        this.Player()
      }

      // transcript: sentences already read are greyed out
      Text() {
        ForEach(this.sentences, (sentence: string, i: number) => {
          Span(i < this.sentences.length - 1 ? `${sentence} ` : sentence)
            .fontColor(i < this.sentencesRead() ? $r('app.color.text_muted') : $r('app.color.text'))
        }, (sentence: string, i: number) => `${i}-${i < this.sentencesRead()}`)
      }
      .fontSize($r('app.float.font_body'))
      .fontFamily(Fonts.REGULAR)
      .lineHeight(24)
      .width('100%')
      .margin({ top: 18 })

      Text($r('app.string.source_wikipedia'))
        .fontSize($r('app.float.font_caption'))
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 20 })
      Text($r('app.string.photo_credit'))
        .fontSize($r('app.float.font_caption'))
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 2, bottom: 20 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 20, right: 20, top: 20 })
  }

  @Builder
  Player() {
    Row({ space: 14 }) {
      Button({ type: ButtonType.Normal }) {
        Image(this.playing ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
          .width(this.playing ? 16 : 18)
          .height(this.playing ? 16 : 18)
      }
      .width($r('app.float.play_button_size'))
      .height($r('app.float.play_button_size'))
      .borderRadius($r('app.float.radius'))
      .backgroundColor($r('app.color.accent'))
      .accessibilityText(this.playing ? $r('app.string.a11y_pause') : $r('app.string.a11y_play'))
      .onClick(() => this.togglePlay())

      Column({ space: 8 }) {
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height($r('app.float.progress_height')).backgroundColor($r('app.color.progress_track'))
          Row()
            .width(`${Math.round(this.progress() * 100)}%`)
            .height($r('app.float.progress_height'))
            .backgroundColor($r('app.color.accent'))
        }
        .width('100%')
        Row() {
          this.Time(this.positionMs)
          Blank()
          this.Time(this.durationMs)
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  Time(ms: number) {
    Text(clock(ms))
      .fontSize($r('app.float.font_caption'))
      .fontFamily(Fonts.SEMIBOLD)
      .fontColor($r('app.color.text_secondary'))
  }

  @Builder
  MoreSheet() {
    Column({ space: 8 }) {
      Text(this.place?.name ?? '')
        .fontSize($r('app.float.font_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
      Text($r('app.string.source_wikipedia'))
        .fontSize($r('app.float.font_caption'))
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
      Text(this.place?.summary ?? '')
        .fontSize($r('app.float.font_body'))
        .fontFamily(Fonts.REGULAR)
        .lineHeight(22)
        .fontColor($r('app.color.text'))
        .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 20 + this.bottomInset })
  }

  // ---- loading ----

  /** Photos and narration in parallel; the screen switches when both are done. */
  private async load(place: Place): Promise<void> {
    const results = await Promise.all<string[] | Segment>([this.loadPhotos(place), this.loadNarration(place)]);
    this.photos = results[0] as string[];
    const segment = results[1] as Segment;
    this.segment = segment;
    this.sentences = splitSentences(segment.text);
    this.durationMs = segment.durationMs ?? 0;
    this.getUIContext().animateTo({ duration: 300 }, () => {
      this.loading = false;
    });
    if (segment.audioUrl !== null) {
      this.startAudio(segment.audioUrl);
    }
  }

  private async loadNarration(place: Place): Promise<Segment> {
    return Services.narration().request({
      kind: SegmentKind.ARRIVAL,
      poiId: place.id,
      fromPoiId: null,
      interests: Settings.interestList(),
      maxWords: NARRATION_WORDS,
      voice: true,
    }, NARRATION_TIMEOUT_MS);
  }

  /** The queue photo first, then other photos of the article (Wikimedia Commons, maps and icons skipped). */
  private async loadPhotos(place: Place): Promise<string[]> {
    const photos: string[] = [placeImage(place)];
    const api = mediaListUrl(place.sourceUrl);
    if (api === null) {
      return photos;
    }
    const text = await fetchText(api);
    if (text === null) {
      return photos;
    }
    try {
      const list = JSON.parse(text) as MediaList;
      for (const item of list.items ?? []) {
        if (photos.length >= MAX_PHOTOS) {
          break;
        }
        const src = item.srcset !== undefined && item.srcset.length > 0 ? item.srcset[item.srcset.length - 1].src : '';
        if (item.type === 'image' && item.showInGallery && isPhoto(item.title) && src.length > 0 &&
          !samePhoto(src, place.imageUrl)) {
          photos.push(src.startsWith('//') ? `https:${src}` : src);
        }
      }
    } catch (e) {
      // the first photo is enough
    }
    return photos;
  }

  // ---- audio ----

  private startAudio(url: string): void {
    this.started = true;
    const listener: PlaybackListener = {
      onProgress: (positionMs: number, durationMs: number) => {
        this.positionMs = positionMs;
        if (durationMs > 0) {
          this.durationMs = durationMs;
        }
      },
      onStateChange: (playing: boolean) => {
        this.playing = playing;
      },
    };
    this.player.playUrl(url, listener);
  }

  private togglePlay(): void {
    if (this.playing) {
      this.player.pause();
    } else if (this.started) {
      this.player.resume();
    } else if (this.segment?.audioUrl) {
      this.startAudio(this.segment.audioUrl);
    }
  }

  // ---- view helpers ----

  private hasAudio(): boolean {
    return this.segment !== null && this.segment.audioUrl !== null;
  }

  private originLabel(): Resource {
    if (this.segment?.origin === SegmentOrigin.AI) {
      return $r('app.string.narration_ai');
    }
    return $r('app.string.narration_template');
  }

  private isSaved(id: string): boolean {
    return this.saved.some((p: Place) => p.id === id);
  }

  private progress(): number {
    return this.durationMs > 0 ? Math.min(1, this.positionMs / this.durationMs) : 0;
  }

  /** Sentences already read, assuming each takes time in proportion to its length. */
  private sentencesRead(): number {
    if (!this.hasAudio()) {
      return 0;
    }
    const total = this.sentences.reduce((sum: number, t: string) => sum + t.length, 0);
    let read = 0;
    let acc = 0;
    for (const t of this.sentences) {
      acc += t.length;
      if (total > 0 && acc / total <= this.progress()) {
        read++;
      }
    }
    return read;
  }
}

function clock(ms: number): string {
  const s = Math.round(ms / 1000);
  return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`;
}

/** https://pl.wikipedia.org/wiki/Barbakan_w_Krakowie -> .../api/rest_v1/page/media-list/Barbakan_w_Krakowie */
function mediaListUrl(sourceUrl: string): string | null {
  const match = new RegExp('^(https://[a-z]+\\.wikipedia\\.org)/wiki/(.+)$').exec(sourceUrl);
  return match === null ? null : `${match[1]}/api/rest_v1/page/media-list/${match[2]}`;
}

function isPhoto(title: string): boolean {
  const t = title.toLowerCase();
  return (t.endsWith('.jpg') || t.endsWith('.jpeg')) && !t.includes('map') && !t.includes('mapa') &&
    !t.includes('herb') && !t.includes('logo');
}

/** Same Commons file in another size: compare the file name in the thumbnail path. */
function samePhoto(a: string, b: string): boolean {
  const file = (url: string): string => {
    const parts = url.split('?')[0].split('/');
    return parts.length >= 2 ? parts[parts.length - 2] : url;
  };
  return file(a) === file(b);
}
