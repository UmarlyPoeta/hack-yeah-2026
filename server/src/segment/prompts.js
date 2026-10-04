// Polish prompts per segment kind for Bielik (#18). Bump PROMPT_VERSION on any change: it is part of the cache key.
export const PROMPT_VERSION = 'p2';

export const SEGMENT_SCHEMA = {
  type: 'object',
  properties: {
    title: { type: 'string' },
    text: { type: 'string' },
    claims: {
      type: 'array',
      maxItems: 4,
      items: {
        type: 'object',
        properties: { text: { type: 'string' }, quote: { type: 'string' } },
        required: ['text', 'quote'],
      },
    },
  },
  required: ['text', 'claims'],
};

const SOURCE_MAX_CHARS = { ARRIVAL: 3000, WELCOME: 1500, BRIDGE: 2000, DEEP_DIVE: 7000 };

const INTEREST_HINT = {
  architektura: 'architekturę i wygląd budynku',
  historia: 'historię i ważne wydarzenia',
  sztuka: 'sztukę i artystów',
  ludzie: 'ludzi związanych z miejscem',
  legendy: 'legendy i ciekawostki',
};

export const SYSTEM_PROMPT = [
  'Jesteś przewodnikiem miejskim, który idzie razem ze słuchaczem po Krakowie i mówi mu do ucha.',
  'Piszesz po polsku tekst do przeczytania na głos: krótkie zdania, naturalnie, ciepło, w drugiej osobie albo „my”.',
  'Zwykły tekst: bez Markdownu, gwiazdek, nagłówków, list, numeracji, nawiasów i emotikonów. Daty zapisuj cyframi tak jak w źródle.',
  'Używasz WYŁĄCZNIE faktów ze ŹRÓDŁA. Opowiadasz własnymi słowami, nie przepisuj źródła zdanie po zdaniu.',
  'Nie podawaj żadnej liczby ani daty, której nie ma w źródle. Jeśli źródło czegoś nie mówi, pomiń to.',
  'Dla 2–4 najważniejszych faktów dodaj w polu claims obiekt {text, quote}: quote to DOSŁOWNY fragment',
  'jednego zdania źródła (5–12 słów), skopiowany znak w znak. Nie łącz zdań i nie dopisuj nic od siebie.',
  'Odpowiadasz wyłącznie JSON-em zgodnym ze schematem.',
].join(' ');

function interestsLine(interests) {
  const hints = interests.map((i) => INTEREST_HINT[i]).filter(Boolean);
  return hints.length ? `Słuchacza najbardziej interesuje: ${hints.join(', ')}.` : '';
}

function clip(text, kind) {
  const max = SOURCE_MAX_CHARS[kind] ?? 3000;
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

/**
 * @param {{ kind: string, maxWords: number, interests: string[] }} req
 * @param {{ name: string }} poi
 * @param {{ name: string } | null} fromPoi BRIDGE only
 * @param {{ target: string, from?: string }} source source texts, already chosen by the server
 * @returns {{ user: string, sourceText: string }} sourceText = everything the validator may accept quotes from
 */
export function buildPrompt(req, poi, fromPoi, source) {
  const budget = `Długość: około ${req.maxWords} słów (nie więcej niż ${Math.ceil(req.maxWords * 1.2)}).`;
  const interests = interestsLine(req.interests);
  const target = clip(source.target, req.kind);
  let task;
  let sourceBlock;
  let sourceText = target;
  switch (req.kind) {
    case 'WELCOME':
      task = `Powitaj słuchacza na początku spaceru i zapowiedz pierwszy przystanek: ${poi.name}. Zaciekaw jednym faktem, ale nie opowiadaj jeszcze wszystkiego.`;
      sourceBlock = `ŹRÓDŁO (${poi.name}):\n${target}`;
      break;
    case 'ARRIVAL':
      task = `Właśnie stoimy przy: ${poi.name}. Opowiedz, na co patrzymy i dlaczego to miejsce jest ważne.`;
      sourceBlock = `ŹRÓDŁO (${poi.name}):\n${target}`;
      break;
    case 'BRIDGE': {
      const from = clip(source.from ?? '', req.kind);
      task =
        `Idziemy od: ${fromPoi.name} do: ${poi.name}. Połącz oba miejsca jednym wspólnym wątkiem z obu źródeł ` +
        `(epoka, ludzie, funkcja, styl). Zakończ zapowiedzią miejsca, do którego idziemy. Nie opisuj ich szczegółowo.`;
      sourceBlock = `ŹRÓDŁO 1 (${fromPoi.name}):\n${from}\n\nŹRÓDŁO 2 (${poi.name}):\n${target}`;
      sourceText = `${from}\n${target}`;
      break;
    }
    case 'DEEP_DIVE':
      task = `Słuchacz zatrzymał się przy: ${poi.name} i chce usłyszeć więcej. Opowiedz pogłębioną historię w kilku akapitach, od najciekawszego wątku.`;
      sourceBlock = `ŹRÓDŁO (${poi.name}):\n${target}`;
      break;
    default:
      throw new Error(`no prompt for ${req.kind}`);
  }
  const user = [`Typ segmentu: ${req.kind}.`, task, interests, budget, '', sourceBlock].filter((l) => l !== '').join('\n');
  return { user, sourceText };
}

/** Second attempt after a failed validation: the same prompt plus what was wrong. */
export function retryPrompt(user, problems) {
  return (
    `${user}\n\nPOPRZEDNIA ODPOWIEDŹ ODRZUCONA: ${problems.slice(0, 5).join('; ')}.\n` +
    'Popraw: cytaty (quote) kopiuj ze źródła dosłownie, a w tekście używaj tylko liczb i dat obecnych w źródle.'
  );
}

/** Ollama num_predict for a word budget: Polish is ~2.5 tokens/word, plus JSON and claims. */
export function numPredict(maxWords) {
  return Math.round(maxWords * 3 + 250);
}
