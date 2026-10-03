import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { sentences, leadSentences } from '../src/segment/templates.js';
import { cleanText, normalize, numbersIn, validateSegment } from '../src/validate/grounding.js';

const SOURCE =
  'Kamienica Czyncielów – kamienica przy Rynku Głównym 4. W latach 1898–1901 w kamienicy wynajmował pokój ' +
  'Stanisław Wyspiański. Na przełomie 1900 i 1901 roku napisał tu „Wesele”.';

describe('grounding validator', () => {
  it('accepts quotes that differ only in case, quotes, dashes and spaces', () => {
    const r = validateSegment(
      {
        text: 'Tu, w latach 1898–1901, mieszkał Wyspiański i napisał Wesele.',
        claims: [
          { text: 'Mieszkał tu Wyspiański', quote: 'W latach 1898-1901 w kamienicy  wynajmował pokój Stanisław Wyspiański' },
          { text: 'Napisał Wesele', quote: 'napisał tu "Wesele"' },
        ],
      },
      SOURCE,
      { maxWords: 60 },
    );
    assert.deepEqual(r.problems, []);
    assert.equal(r.claims.length, 2);
  });

  it('rejects a made-up quote', () => {
    const r = validateSegment({ text: 'Mieszkał tu Wyspiański.', claims: [{ text: 'x', quote: 'Wyspiański mieszkał tu przez całe życie' }] }, SOURCE, { maxWords: 60 });
    assert.equal(r.ok, false);
    assert.match(r.problems[0], /^quote_not_in_source/);
  });

  it('accepts a near-verbatim quote (period added, one ending changed) and drops a minority of bad claims', () => {
    const r = validateSegment(
      {
        text: 'Wyspiański wynajmował tu pokój.',
        claims: [
          { text: 'a', quote: 'W latach 1898–1901 w kamienicy wynajmowała pokój Stanisław Wyspiański.' },
          { text: 'b', quote: 'napisał tu „Wesele”' },
          { text: 'c', quote: 'Wyspiański mieszkał tu przez całe życie' },
        ],
      },
      SOURCE,
      { maxWords: 60 },
    );
    assert.equal(r.ok, true);
    assert.deepEqual(r.claims.map((c) => c.text), ['a', 'b']);
  });

  it('rejects when more claims are bad than good', () => {
    const r = validateSegment(
      { text: 'Tekst.', claims: [{ text: 'a', quote: 'napisał tu „Wesele”' }, { text: 'b', quote: 'zupełnie inne zdanie o niczym' }, { text: 'c', quote: 'kolejne zmyślone zdanie bez źródła' }] },
      SOURCE,
      { maxWords: 60 },
    );
    assert.equal(r.ok, false);
  });

  it('rejects a year that is not in the source', () => {
    const r = validateSegment({ text: 'Wyspiański napisał tu Wesele w 1905 roku.', claims: [{ text: 'x', quote: 'napisał tu „Wesele”' }] }, SOURCE, { maxWords: 60 });
    assert.deepEqual(r.problems, ['number_not_in_source: 1905']);
  });

  it('rejects empty text, missing claims and far too long text', () => {
    assert.deepEqual(validateSegment({ text: ' ', claims: [] }, SOURCE, { maxWords: 60 }).problems, ['empty_text']);
    assert.deepEqual(validateSegment({ text: 'Tekst.' }, SOURCE, { maxWords: 60 }).problems, ['no_claims_array']);
    const long = validateSegment({ text: 'słowo '.repeat(100), claims: [{ text: 'x', quote: 'Rynku Głównym 4' }] }, SOURCE, { maxWords: 20 });
    assert.deepEqual(long.problems, ['too_long']);
  });

  it('cleanText strips Markdown and list numbering', () => {
    assert.equal(cleanText('1. Tu napisał **Wesele**.\n2. A _potem_ odszedł.'), 'Tu napisał Wesele. A potem odszedł.');
    // emoji Bielik produced in the #25 eval (castle, crown, smiley), written as code points
    assert.equal(cleanText('Słuchaczu, zatrzymajmy się przy Barbakanie.'), 'Zatrzymajmy się przy Barbakanie.');
    assert.equal(cleanText('Drogi słuchaczu! oto Sukiennice.'), 'Oto Sukiennice.');
    assert.equal(cleanText('Wyspiański pisał dla słuchaczy teatru.'), 'Wyspiański pisał dla słuchaczy teatru.');
    assert.equal(cleanText('Brama \u{1F3F0} przetrwała. \u{1F451} Kościół** stoi.\\nDziś \u{1F60A}'), 'Brama przetrwała. Kościół stoi. Dziś');
  });

  it('normalizes typography and splits number groups', () => {
    assert.equal(normalize('„Wesele”  –  dramat'), '"wesele" - dramat');
    assert.deepEqual(numbersIn('W latach 1907–1908, ok. 1 500 osób'), ['1907', '1908', '1500']);
  });
});

describe('templates', () => {
  it('splits sentences but keeps Polish abbreviations together', () => {
    assert.deepEqual(sentences('Stoi przy ul. Floriańskiej. Zbudowano ją w XV w. Potem ją przebudowano.'), [
      'Stoi przy ul. Floriańskiej.',
      'Zbudowano ją w XV w. Potem ją przebudowano.',
    ]);
  });

  it('leadSentences respects the word budget', () => {
    const text = 'Jedno dwa trzy cztery. Pięć sześć siedem osiem. Dziewięć dziesięć.';
    assert.equal(leadSentences(text, 3, 8), 'Jedno dwa trzy cztery. Pięć sześć siedem osiem.');
    assert.equal(leadSentences(text, 3, 2), 'Jedno dwa…');
  });
});
