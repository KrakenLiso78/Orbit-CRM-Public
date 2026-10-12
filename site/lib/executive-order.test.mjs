import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const pageSource = readFileSync(
  fileURLToPath(new URL('../app/demo/market/page.tsx', import.meta.url)),
  'utf8',
);
const stylesheet = readFileSync(
  fileURLToPath(new URL('../app/globals.css', import.meta.url)),
  'utf8',
);

void test('the executive narrative precedes the synthetic 25-company graphic and list', () => {
  const sectionStart = pageSource.indexOf('<section className="shell executive"');
  const narrative = pageSource.indexOf('className="executive-narrative"', sectionStart);
  const graphic = pageSource.indexOf('<RankFlow lang={lang} />', sectionStart);
  const expandedList = pageSource.indexOf('<MarketUniverse lang={lang} />', sectionStart);

  assert.ok(sectionStart >= 0, 'executive section must exist');
  assert.ok(narrative > sectionStart, 'executive narrative must be inside the section');
  assert.ok(graphic > narrative, '25-company graphic must follow the executive narrative');
  assert.ok(expandedList > graphic, 'expanded company list must follow the graphic');
});

void test('the executive narrative fills its track with the reduced responsive type scale', () => {
  const rule = stylesheet.match(/\.executive\s*>\s*\.executive-narrative\s*\{([^}]*)\}/)?.[1] ?? '';

  assert.match(rule, /width:\s*100%/);
  assert.match(rule, /max-width:\s*none/);
  assert.match(rule, /font-size:\s*clamp\(21px,\s*2\.4vw,\s*32px\)/);
});
