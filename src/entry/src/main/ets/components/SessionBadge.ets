@Component
export struct SessionBadge {
  @Prop sessionState: string = 'WALKING';

  build() {
    Row() {
      Text(this.getSessionText())
        .fontSize(12)
        .fontColor(this.getSessionColor())
        .fontWeight(FontWeight.Bold)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor('#F0F0F0')
    .borderRadius(6)
  }

  private getSessionText(): string {
    switch (this.sessionState) {
      case 'WALKING': return '🟢 WALKING';
      case 'ACQUIRING': return '🟡 ACQUIRING GPS';
      case 'PAUSED': return '⏸️ PAUSED';
      case 'ERROR': return '🔴 ERROR';
      default: return '⚪ IDLE';
    }
  }

  private getSessionColor(): ResourceColor {
    switch (this.sessionState) {
      case 'WALKING': return Color.Green;
      case 'ACQUIRING': return '#FAAD14';
      case 'PAUSED': return Color.Orange;
      case 'ERROR': return Color.Red;
      default: return Color.Gray;
    }
  }
}