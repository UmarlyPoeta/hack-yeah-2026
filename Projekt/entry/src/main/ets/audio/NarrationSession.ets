// System media session for the narration (AVSession Kit): the place's photo and name with play/pause and
// seeking on the lock screen and in the control centre, so the guide can be heard with the phone in a pocket.
// Tapping the session opens the place again.
import { avSession } from '@kit.AVSessionKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Place, shortName } from '../model/Place';

const DOMAIN: number = 0x0000;
const TAG: string = 'NarrationSession';

export interface SessionControls {
  play: () => void;
  pause: () => void;
  seek: (positionMs: number) => void;
}

export class NarrationSession {
  private session: avSession.AVSession | null = null;
  private durationMs: number = 0;

  async start(context: common.Context, place: Place, durationMs: number, controls: SessionControls): Promise<void> {
    try {
      const session = await avSession.createAVSession(context, 'tour', 'audio');
      this.session = session;
      this.durationMs = durationMs;
      const metadata: avSession.AVMetadata = {
        assetId: place.id,
        title: shortName(place),
        artist: 'tour',
        description: place.summary.slice(0, 120),
        duration: durationMs,
      };
      const picture = await NarrationSession.pixelMap(place.imageFile);
      if (picture !== null) {
        metadata.mediaImage = picture;
      } else if (place.imageUrl.length > 0) {
        metadata.mediaImage = place.imageUrl;
      }
      await session.setAVMetadata(metadata);
      session.on('play', () => controls.play());
      session.on('pause', () => controls.pause());
      session.on('stop', () => controls.pause());
      session.on('seek', (time: number) => controls.seek(time));
      await session.setLaunchAbility(await wantAgent.getWantAgent({
        wants: [{ bundleName: context.applicationInfo.name, abilityName: 'EntryAbility', parameters: { placeId: place.id } }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 3,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      }));
      await session.activate();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'no media session: %{public}s', JSON.stringify(e));
    }
  }

  /** Mirrors the player's state; the system moves the progress bar on its own from updateTime. */
  update(playing: boolean, positionMs: number, durationMs: number): void {
    if (this.session === null) {
      return;
    }
    if (durationMs > 0 && durationMs !== this.durationMs) {
      this.durationMs = durationMs;
    }
    const state: avSession.AVPlaybackState = {
      state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      speed: 1,
      position: { elapsedTime: positionMs, updateTime: Date.now() },
    };
    this.session.setAVPlaybackState(state).catch(() => {
      // session already gone
    });
  }

  async end(): Promise<void> {
    const session = this.session;
    this.session = null;
    if (session === null) {
      return;
    }
    try {
      session.off('play');
      session.off('pause');
      session.off('stop');
      session.off('seek');
      await session.deactivate();
      await session.destroy();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'end failed: %{public}s', JSON.stringify(e));
    }
  }

  private static async pixelMap(path: string): Promise<image.PixelMap | null> {
    if (path.length === 0) {
      return null;
    }
    try {
      const source = image.createImageSource(path);
      const map = await source.createPixelMap({ desiredSize: { width: 512, height: 512 } });
      source.release();
      return map;
    } catch (e) {
      return null;
    }
  }
}
