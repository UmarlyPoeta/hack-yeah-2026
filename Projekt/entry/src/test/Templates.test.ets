import { describe, it, expect } from '@ohos/hypium';
import { Side } from '../main/ets/guide/Itinerary';
import { approachText, missedText, splitSentences, takeWords } from '../main/ets/guide/Templates';
import { poiAt } from './TestGeo';

export default function templatesTest() {
  describe('templates', () => {
    it('sentencesKeepAbbreviations', 0, () => {
      const s: string[] = splitSentences('Brama (Brama św. Floriana) stoi przy ul. Pijarskiej. Ufundował ją J. Matejko. Tak.');
      expect(s.length).assertEqual(3);
      expect(s[0]).assertEqual('Brama (Brama św. Floriana) stoi przy ul. Pijarskiej.');
    });
    it('takeWordsWholeSentences', 0, () => {
      expect(takeWords('Jeden dwa trzy. Cztery pięć sześć. Siedem osiem dziewięć.', 7))
        .assertEqual('Jeden dwa trzy. Cztery pięć sześć.');
      expect(takeWords('Bardzo długie pierwsze zdanie bez kropki', 3)).assertEqual('Bardzo długie pierwsze…');
    });
    it('approachAndMissed', 0, () => {
      expect(approachText(poiAt('Barbakan', 0, 0), 43, Side.RIGHT)).assertEqual('Za około 40 metrów po prawej: Barbakan.');
      expect(approachText(poiAt('Barbakan', 0, 0), 12, Side.LEFT)).assertEqual('Tuż obok, po lewej: Barbakan.');
      expect(missedText(poiAt('Barbakan', 0, 0), Side.LEFT)).assertEqual('Po lewej, już za nami: Barbakan.');
    });
  });
}
