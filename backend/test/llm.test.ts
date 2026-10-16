import assert from 'node:assert/strict';
import { afterEach, describe, it } from 'node:test';
import { generateTurn, LlmFormatError, parseAiTurn } from '../src/providers/llm.ts';
import { UpstreamError } from '../src/http.ts';
import { aiTurn, claudeReply, json, makeConfig, mockFetch } from './helpers.ts';

let restore = () => {};
afterEach(() => restore());

describe('parseAiTurn', () => {
  it('reads a clean object', () => {
    const t = parseAiTurn(JSON.stringify(aiTurn({ has_mistake: true })));
    assert.equal(t.has_mistake, true);
    assert.equal(t.emotion_tone, 'happy');
  });

  it('tolerates a code fence and text around it', () => {
    const t = parseAiTurn('Sure!\n```json\n' + JSON.stringify(aiTurn()) + '\n```');
    assert.equal(t.reply_japanese, 'そうですか。');
  });

  it('coerces string booleans and unknown emotions', () => {
    const t = parseAiTurn(
      JSON.stringify({ ...aiTurn(), has_mistake: 'true', conversation_completed: 'false', emotion_tone: 'furious' }),
    );
    assert.equal(t.has_mistake, true);
    assert.equal(t.conversation_completed, false);
    assert.equal(t.emotion_tone, 'calm');
  });

  it('rejects missing or empty required fields and non-JSON', () => {
    assert.throws(() => parseAiTurn('no json here'), LlmFormatError);
    assert.throws(() => parseAiTurn('{"correction_ar":"x"}'), LlmFormatError);
    assert.throws(() => parseAiTurn(JSON.stringify(aiTurn({ reply_japanese: '  ' }))), LlmFormatError);
    assert.throws(() => parseAiTurn('{bad json}'), LlmFormatError);
  });
});

describe('generateTurn', () => {
  it('sends the system prompt (cached), history and the new message', async () => {
    const m = mockFetch(() => claudeReply(aiTurn()));
    restore = m.restore;
    const cfg = makeConfig({ ANTHROPIC_MODEL: 'claude-test' });
    await generateTurn(cfg, 'SYSTEM', [{ role: 'user', content: 'a' }, { role: 'assistant', content: 'b' }], 'c');
    const call = m.calls[0]!;
    assert.equal(call.url, 'https://api.anthropic.com/v1/messages');
    assert.equal(call.json.model, 'claude-test');
    assert.equal(call.json.system[0].text, 'SYSTEM');
    assert.deepEqual(call.json.system[0].cache_control, { type: 'ephemeral' });
    assert.deepEqual(call.json.messages.map((x: any) => x.content), ['a', 'b', 'c']);
    assert.equal((call.init.headers as any)['x-api-key'], 'sk-ant-test');
    assert.equal(call.json.temperature, undefined);
  });

  it('asks once more when the first answer is not JSON', async () => {
    let n = 0;
    const m = mockFetch(() => (++n === 1 ? claudeReply('Sorry, here you go: hello') : claudeReply(aiTurn())));
    restore = m.restore;
    const t = await generateTurn(makeConfig(), 'S', [], 'hi');
    assert.equal(t.reply_japanese, 'そうですか。');
    assert.equal(m.calls.length, 2);
    assert.match(m.calls[1]!.json.messages.at(-1).content, /exactly ONE JSON object/);
  });

  it('gives up with LlmFormatError after the second bad answer', async () => {
    const m = mockFetch(() => claudeReply('still not json'));
    restore = m.restore;
    await assert.rejects(generateTurn(makeConfig(), 'S', [], 'hi'), LlmFormatError);
    assert.equal(m.calls.length, 2);
  });

  it('retries a 529 once, then succeeds', async () => {
    let n = 0;
    const m = mockFetch(() => (++n === 1 ? json({ error: 'overloaded' }, 529) : claudeReply(aiTurn())));
    restore = m.restore;
    await generateTurn(makeConfig(), 'S', [], 'hi');
    assert.equal(m.calls.length, 2);
  });

  it('does not retry a 400', async () => {
    const m = mockFetch(() => json({ error: 'bad' }, 400));
    restore = m.restore;
    await assert.rejects(generateTurn(makeConfig(), 'S', [], 'hi'), UpstreamError);
    assert.equal(m.calls.length, 1);
  });
});
