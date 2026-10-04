import media from '@ohos.multimedia.media';
import common from '@ohos.app.ability.common';

/** Progress of a stream started with playUrl(); times in ms. */
export interface PlaybackListener {
  onProgress: (positionMs: number, durationMs: number) => void;
  onStateChange: (playing: boolean) => void;
}

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

      // Pobieramy deskryptor i ustawiamy źródło (to przełączy stan z idle na initialized)
      let fdPath = await context.resourceManager.getRawFd(fileName);
      this.avPlayer.fdSrc = { fd: fdPath.fd, offset: fdPath.offset, length: fdPath.length };

    } catch (error) {
      console.error('Błąd odtwarzania: ' + JSON.stringify(error));
    }
  }

  /** Streams a remote file (e.g. the server's /v1/audio/<id>.mp3) and reports progress. */
  async playUrl(url: string, listener: PlaybackListener) {
    try {
      if (this.avPlayer) {
        await this.avPlayer.release();
        this.avPlayer = null;
      }
      const player = await media.createAVPlayer();
      this.avPlayer = player;
      let durationMs = 0;
      player.on('durationUpdate', (d: number) => {
        durationMs = d;
      });
      player.on('timeUpdate', (t: number) => {
        listener.onProgress(t, durationMs);
      });
      player.on('stateChange', (state: string) => {
        switch (state) {
          case 'initialized':
            player.prepare();
            break;
          case 'prepared':
            player.play();
            break;
          case 'playing':
            listener.onStateChange(true);
            break;
          case 'paused':
          case 'stopped':
          case 'error':
            listener.onStateChange(false);
            break;
          case 'completed':
            listener.onProgress(durationMs, durationMs);
            listener.onStateChange(false);
            break;
          default:
            break;
        }
      });
      player.url = url;
    } catch (error) {
      console.error('Błąd odtwarzania: ' + JSON.stringify(error));
      listener.onStateChange(false);
    }
  }

  pause() {
    this.avPlayer?.pause();
  }

  /** Continues after pause(), or starts again after the end. */
  resume() {
    const player = this.avPlayer;
    if (player === null) {
      return;
    }
    if (player.state === 'completed') {
      player.seek(0);
    }
    player.play();
  }

  release() {
    if (this.avPlayer) {
      this.avPlayer.release();
      this.avPlayer = null;
    }
  }
}