import { media } from '@ohos.multimedia.media';
import common from '@ohos.app.ability.common';

export class NarratorPlayer {
  private avPlayer: media.AVPlayer | null = null;

  async playRawFile(context: common.Context, fileName: string) {
    try {
      this.avPlayer = await media.createAVPlayer();
      this.avPlayer.on('stateChange', async (state) => {
        if (state === 'initialized') {
          let fdPath = await context.resourceManager.getRawFd(fileName);
          this.avPlayer!.fdSrc = { fd: fdPath.fd, offset: fdPath.offset, length: fdPath.length };
        } else if (state === 'prepared') {
          this.avPlayer!.prepare();
        } else if (state === 'completed') {
          this.release();
        }
      });
      this.avPlayer.state = 'idle';
    } catch (error) {
      console.error('B³¹d odtwarzania: ' + JSON.stringify(error));
    }
  }

  release() {
    if (this.avPlayer) {
      this.avPlayer.release();
      this.avPlayer = null;
    }
  }
}
