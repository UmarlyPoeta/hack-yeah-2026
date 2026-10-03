import { Palette } from '../common/Theme';

@Component
export struct SessionBadge {
  @Prop sessionState: string = 'WALKING';
  @State private breath: number = 1;

  build() {
    Row({ space: 7 }) {
      Circle({ width: 7, height: 7 })
        .fill(this.getSessionColor())
        .opacity(this.sessionState === 'WALKING' || this.sessionState === 'ACQUIRING' ? this.breath : 1)
        .onAppear(() => {
          this.getUIContext().animateTo({
            duration: 1100, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate
          }, () => {
            this.breath = 0.25;
          });
        })
      Text(this.getSessionText())
        .fontSize(13)
        .fontColor(Palette.INK_SOFT)
    }
    .padding({ left: 10, right: 12, top: 6, bottom: 6 })
    .border({ width: 1, color: Palette.RULE, radius: 14 })
  }

  private getSessionText(): string {
    switch (this.sessionState) {
      case 'WALKING': return 'W drodze';
      case 'ACQUIRING': return 'Szukam pozycji';
      case 'PAUSED': return 'Wstrzymany';
      case 'ERROR': return 'Brak pozycji';
      default: return 'Gotowy';
    }
  }

  private getSessionColor(): string {
    switch (this.sessionState) {
      case 'WALKING': return Palette.MOSS;
      case 'ACQUIRING': return Palette.AMBER;
      case 'PAUSED': return Palette.INK_FAINT;
      case 'ERROR': return Palette.BRICK;
      default: return Palette.INK_FAINT;
    }
  }
}
