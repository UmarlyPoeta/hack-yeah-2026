import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Side } from '../src/guide/Itinerary';
import { approachText, arrivalText, countWords, displayName, missedText, splitSentences, takeWords } from '../src/guide/Templates';
import { poiAt } from './helpers';

test('sentences: abbreviations, initials and Roman numerals do not split', () => {
  const s = splitSentences('Brama (Brama św. Floriana) stoi przy ul. Pijarskiej. Ufundował ją J. Matejko w XIX w. Dziś jest muzeum! Czy na pewno? Tak.');
  assert.deepEqual(s, [
    'Brama (Brama św. Floriana) stoi przy ul. Pijarskiej.',
    'Ufundował ją J. Matejko w XIX w. Dziś jest muzeum!',   // "w." is ambiguous: kept together, never cut mid-phrase
    'Czy na pewno?',
    'Tak.'
  ]);
});

test('takeWords keeps whole sentences within the budget, cuts only an over-long first sentence', () => {
  const text = 'Jeden dwa trzy. Cztery pięć sześć. Siedem osiem dziewięć.';
  assert.equal(takeWords(text, 6), 'Jeden dwa trzy. Cztery pięć sześć.');
  assert.equal(takeWords(text, 7), 'Jeden dwa trzy. Cztery pięć sześć.');
  assert.equal(takeWords('Bardzo długie pierwsze zdanie bez kropki na końcu', 3), 'Bardzo długie pierwsze…');
  assert.equal(takeWords('', 10), '');
});

test('display names drop the city suffix and trailing brackets', () => {
  const p = poiAt('x', 0, 0);
  p.name = 'Dom Wita Stwosza w Krakowie';
  assert.equal(displayName(p), 'Dom Wita Stwosza');
  p.name = 'Kościół św. Marii Magdaleny w Krakowie (Stare Miasto)';
  assert.equal(displayName(p), 'Kościół św. Marii Magdaleny');
  p.name = 'Kaplica Zygmuntowska na Wawelu';
  assert.equal(displayName(p), 'Kaplica Zygmuntowska na Wawelu');
});

test('approach, missed and arrival read naturally', () => {
  const p = poiAt('Barbakan', 0, 0);
  assert.equal(approachText(p, 43, Side.RIGHT), 'Za około 40 metrów po prawej: Barbakan.');
  assert.equal(approachText(p, 12, Side.LEFT), 'Tuż obok, po lewej: Barbakan.');
  assert.equal(missedText(p, Side.LEFT), 'Po lewej, już za nami: Barbakan.');
  const a = arrivalText(p, 40, [poiAt('Galeria', 0, 0)]);
  assert.ok(a.endsWith('Obok: Galeria.'), a);
  assert.ok(countWords(a) <= 40);
});
