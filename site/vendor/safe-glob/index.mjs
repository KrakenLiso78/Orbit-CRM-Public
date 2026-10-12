import { globSync } from 'tinyglobby';

// This adapter implements only the synchronous API used by the pinned
// vite-plugin-dynamic-import dependency. Unsupported APIs fail explicitly.
const allowedOptions = new Set(['cwd']);
function boundedPatterns(patterns) {
  const list = typeof patterns === 'string' ? [patterns] : patterns;
  if (!Array.isArray(list) || list.length > 256) throw new RangeError('Too many glob patterns');
  for (const pattern of list) {
    if (typeof pattern !== 'string') throw new TypeError('Glob patterns must be strings');
    if (pattern.length > 4096) throw new RangeError('Glob pattern is too long');
    let groups = 0;
    let bracket = false;
    for (let i = 0; i < pattern.length; i++) {
      const char = pattern[i];
      if (char === '\\') { i++; continue; }
      if (char === '[') { bracket = true; continue; }
      if (char === ']') { bracket = false; continue; }
      if (bracket) continue;
      if (char === '{' || char === '(') {
        if (++groups > 32) throw new RangeError('Glob pattern is too deeply nested');
      } else if (char === '}' || char === ')') groups = Math.max(0, groups - 1);
    }
  }
  return list;
}

export function sync(patterns, options = {}) {
  if (!options || typeof options !== 'object' || Array.isArray(options)) throw new TypeError('Invalid glob options');
  for (const key of Object.keys(options)) {
    if (!allowedOptions.has(key)) throw new TypeError(`Unsupported glob option: ${key}`);
  }
  if (options.cwd !== undefined && typeof options.cwd !== 'string') throw new TypeError('Glob cwd must be a string');
  const list = boundedPatterns(patterns);
  return [...new Set(globSync(list, {cwd:options.cwd, onlyFiles:true, expandDirectories:false, dot:false}))].sort();
}

export default Object.freeze({sync});
