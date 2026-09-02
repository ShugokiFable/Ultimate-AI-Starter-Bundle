/** Check if content looks like a full page (not a component/partial) */
function isFullPage(content) {
  // Document-shape classification only; stripped text is never an HTML sink.
  // codeql[js/incomplete-multi-character-sanitization]
  const stripped = content.replace(/<!--[\s\S]*?-->/g, '');
  return /<!doctype\s|<html[\s>]|<head[\s>]/i.test(stripped);
}

export { isFullPage };
