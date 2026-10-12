import assert from 'node:assert/strict';
import { parseStoredPublishableKey, readStoredPublishableKey } from './orbit-auth-key.mjs';

assert.equal(parseStoredPublishableKey(''), null);
assert.equal(parseStoredPublishableKey('not-json'), null);
assert.equal(parseStoredPublishableKey('{"refresh_token":"token-only"}'), null);
assert.equal(parseStoredPublishableKey('{"publishable_key":" publishable-test ","refresh_token":"refresh-test"}'), 'publishable-test');

const calls = [];
const existing = readStoredPublishableKey({
  execFileSync: (command, args, options) => {
    calls.push({ command, args, options });
    return '{"publishable_key":"publishable-existing","refresh_token":"revoked-refresh"}';
  },
  service: 'Orbit CRM Call Report MCP',
  account: 'owner',
});
assert.equal(existing, 'publishable-existing');
assert.deepEqual(calls[0].args, ['find-generic-password', '-s', 'Orbit CRM Call Report MCP', '-a', 'owner', '-w']);
assert.deepEqual(calls[0].options.stdio, ['ignore', 'pipe', 'ignore']);

const unavailable = readStoredPublishableKey({
  execFileSync: () => { throw new Error('missing'); },
  service: 'Orbit CRM Call Report MCP',
  account: 'owner',
});
assert.equal(unavailable, null);

console.log('orbit-auth-key: passed');

