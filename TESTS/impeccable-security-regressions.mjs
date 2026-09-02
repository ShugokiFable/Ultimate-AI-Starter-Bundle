import assert from 'node:assert/strict';

import { decodeBasicHtml } from '../_CANONICAL-SKILLS/impeccable/scripts/live-manual-edit-evidence.mjs';
import { parseSvelteComponentFile } from '../_CANONICAL-SKILLS/impeccable/scripts/live/svelte-component.mjs';
import { detectText } from '../_CANONICAL-SKILLS/impeccable/scripts/detector/engines/regex/detect-text.mjs';

assert.equal(decodeBasicHtml('&amp;quot;'), '&quot;');
assert.equal(decodeBasicHtml('&quot;&amp;&lt;&gt;&#39;&apos;'), '"&<>\'\'');

const parsed = parseSvelteComponentFile([
  '<script>const bait = "streamline your";</script \t data-impeccable-test>',
  '<main>safe</main>',
  '<style>.safe { color: red; }</style \n data-impeccable-test>',
].join('\n'));
assert.equal(parsed.markup, '<main>safe</main>');
assert.deepEqual(parsed.cssLines, ['.safe { color: red; }']);

const findings = detectText(
  '<!doctype html><html><body><script>streamline your</script \t bogus><main>plain</main></body></html>',
  'fixture.html',
);
assert.equal(findings.some((finding) => finding.antipattern === 'marketing-buzzword'), false);

console.log('impeccable security regressions PASS');
