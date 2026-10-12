// Structure imported field lines for display without rewriting stored evidence.
export function parseNoteFields(text, title = '') {
  const entries = [];
  const paragraphs = [];
  let current = null;
  const normalize = value => value.replace(/^#+\s*/, '').trim().toLowerCase();
  for (const line of text.split(/\r?\n/)) {
    if (normalize(line) === normalize(title)) continue;
    const match = line.match(/^([^:\n]{1,40}):\s*(.*)$/);
    if (match && !/^https?$/i.test(match[1])) {
      current = { label: match[1].trim(), value: match[2] };
      entries.push(current);
    } else if (current && line.trim()) current.value += '\n' + line;
    else if (!current) paragraphs.push(line);
  }
  return { entries, text: paragraphs.join('\n').trim() };
}
