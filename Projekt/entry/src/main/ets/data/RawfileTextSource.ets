import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { TextSource } from './HttpTransport';

/** UTF-8 text file from entry/src/main/resources/rawfile/. */
export class RawfileTextSource implements TextSource {
  private context: common.Context;
  private fileName: string;

  constructor(context: common.Context, fileName: string) {
    this.context = context;
    this.fileName = fileName;
  }

  async read(): Promise<string> {
    const bytes: Uint8Array = await this.context.resourceManager.getRawFileContent(this.fileName);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }
}
