// MP3 duration without ffprobe: walks MPEG Layer III frame headers (CBR and VBR) and sums their samples.
// Within ~80 ms of ffprobe (encoder delay and padding are not subtracted), enough for narration timing.
const BITRATES_V1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
const BITRATES_V2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
const RATES = { 3: [44100, 48000, 32000], 2: [22050, 24000, 16000], 0: [11025, 12000, 8000] };

/** @param {Buffer} buf @returns {number} duration in ms (0 if no frames were found) */
export function mp3DurationMs(buf) {
  let i = 0;
  if (buf.length > 10 && buf.toString('latin1', 0, 3) === 'ID3') {
    i = 10 + ((buf[6] & 0x7f) << 21 | (buf[7] & 0x7f) << 14 | (buf[8] & 0x7f) << 7 | (buf[9] & 0x7f));
  }
  let seconds = 0;
  while (i + 4 <= buf.length) {
    const b1 = buf[i + 1];
    const b2 = buf[i + 2];
    const version = (b1 >> 3) & 3;   // 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
    const layer = (b1 >> 1) & 3;     // 1 = Layer III
    const bitrateIdx = b2 >> 4;
    const rateIdx = (b2 >> 2) & 3;
    if (buf[i] !== 0xff || (b1 & 0xe0) !== 0xe0 || version === 1 || layer !== 1 || bitrateIdx === 0 || bitrateIdx === 15 || rateIdx === 3) {
      i++;
      continue;
    }
    const kbps = (version === 3 ? BITRATES_V1 : BITRATES_V2)[bitrateIdx];
    const rate = RATES[version][rateIdx];
    const samples = version === 3 ? 1152 : 576;
    const frameLen = Math.floor(((samples / 8) * kbps * 1000) / rate) + ((b2 >> 1) & 1);
    // the first frame of a LAME/Xing file is a header (Xing/Info tag) without audio
    const tag = buf.toString('latin1', i + 4, Math.min(i + 48, buf.length));
    if (!(seconds === 0 && (tag.includes('Xing') || tag.includes('Info')))) seconds += samples / rate;
    i += frameLen;
  }
  return Math.round(seconds * 1000);
}
