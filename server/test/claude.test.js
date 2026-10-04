import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ClaudeClient } from '../src/llm/ClaudeClient.js';
import { LlmError } from '../src/llm/OllamaClient.js';
import { createLlm } from '../src/services.js';

function fakeFetch(status, body, calls = []) {
  return async (url, init) => {
    calls.push({ url, init: { ...init, body: JSON.parse(init.body) } });
    return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  };
}

const schema = { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] };

test('chat forces the segment tool and returns its input as JSON content', async () => {
  const calls = [];
  const client = new ClaudeClient({
    apiKey: 'k', model: 'claude-haiku-4-5-20251001',
    fetch: fakeFetch(200, {
      content: [{ type: 'tool_use', name: 'segment', input: { text: 'Stoimy przed Barbakanem.', claims: [] } }],
      usage: { input_tokens: 900, output_tokens: 120 },
    }, calls),
  });
  const out = await client.chat({ system: 'sys', user: 'u', schema, numPredict: 200, timeoutMs: 1000 });
  assert.deepEqual(JSON.parse(out.content), { text: 'Stoimy przed Barbakanem.', claims: [] });
  assert.equal(calls[0].init.headers['x-api-key'], 'k');
  assert.deepEqual(calls[0].init.body.tool_choice, { type: 'tool', name: 'segment' });
  assert.deepEqual(calls[0].init.body.tools[0].input_schema, schema);
  assert.deepEqual(client.usage, { input: 900, output: 120 });
  assert.equal(client.health().ok, true);
});

test('HTTP errors become LlmError unavailable with the status', async () => {
  const client = new ClaudeClient({ apiKey: 'k', model: 'm', fetch: fakeFetch(529, { error: { type: 'overloaded_error' } }) });
  await assert.rejects(client.chat({ system: 's', user: 'u', schema, numPredict: 10, timeoutMs: 1000 }),
    (err) => err instanceof LlmError && err.code === 'unavailable' && err.status === 529);
  assert.equal(client.health().ok, false);
});

test('a reply without the tool call is a bad response', async () => {
  const client = new ClaudeClient({ apiKey: 'k', model: 'm', fetch: fakeFetch(200, { content: [{ type: 'text', text: 'hej' }] }) });
  await assert.rejects(client.chat({ system: 's', user: 'u', schema, numPredict: 10, timeoutMs: 1000 }),
    (err) => err instanceof LlmError && err.code === 'bad_response');
});

test('LLM_PROVIDER picks the client', () => {
  assert.ok(createLlm({ llmProvider: 'claude', anthropicApiKey: 'k', claudeModel: 'm' }) instanceof ClaudeClient);
  assert.equal(createLlm({ llmProvider: 'claude', anthropicApiKey: '', claudeModel: 'm' }), null);
  assert.equal(createLlm({ llmProvider: 'ollama', llmModel: '' }), null);
});
