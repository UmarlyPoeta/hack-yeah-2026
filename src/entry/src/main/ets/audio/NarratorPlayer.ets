import media from '@ohos.multimedia.media';
import common from '@ohos.app.ability.common';

export class NarratorPlayer {
  private avPlayer: media.AVPlayer | null = null;

  async playRawFile(context: common.Context, fileName: string) {
    try {
      if (this.avPlayer) {
        await this.avPlayer.release();
        this.avPlayer = null;
      }

      this.avPlayer = await media.createAVPlayer();

      this.avPlayer.on('stateChange', async (state: string) => {
        switch (state) {
          case 'idle':
            let fdPath = await context.resourceManager.getRawFd(fileName);
            this.avPlayer!.fdSrc = { fd: fdPath.fd, offset: fdPath.offset, length: fdPath.length };
            break;
          case 'initialized':
            this.avPlayer!.prepare();
            break;
          case 'prepared':
            this.avPlayer!.play();
            break;
          case 'completed':
            this.release();
            break;
          default:
            break;
        }
      });
    } catch (error) {
      console.error('Błąd odtwarzania: ' + JSON.stringify(error));
    }
  }

  release() {
    if (this.avPlayer) {
      this.avPlayer.release();
      this.avPlayer = null;
    }
  }
}