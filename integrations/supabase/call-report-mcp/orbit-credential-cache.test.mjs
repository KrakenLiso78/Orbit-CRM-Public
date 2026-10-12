import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir, rmdir, utimes } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createCredentialCache } from './orbit-credential-cache.mjs';
import { createFileLock } from './orbit-refresh-lock.mjs';

let clock = 1_000;
let refreshes = 0;
let saves = 0;
let pendingResolve;
const session = { publishable_key: 'publishable-test', refresh_token: 'refresh-test' };
const refreshSession = async () => {
  refreshes += 1;
  if (pendingResolve) await new Promise((resolve) => { pendingResolve = resolve; });
  return { access_token: `access-${refreshes}`, refresh_token: `refresh-${refreshes}`, expires_in: 120 };
};

const credentials = createCredentialCache({
  readSession: async () => session,
  refreshSession,
  saveSession: async (_saved, token) => { session.refresh_token = token; saves += 1; },
  now: () => clock,
});

const first = await credentials();
const second = await credentials();
assert.equal(first.accessToken, second.accessToken);
assert.equal(refreshes, 1);
assert.equal(saves, 1);

clock += 61_000;
const third = await credentials();
assert.equal(third.accessToken, 'access-2');
assert.equal(refreshes, 2);

clock += 61_000;
let release;
pendingResolve = () => release?.();
const concurrentA = credentials();
const concurrentB = credentials();
await new Promise((resolve) => setTimeout(resolve, 0));
assert.equal(refreshes, 3);
release = () => {};
pendingResolve();
await Promise.all([concurrentA, concurrentB]);
assert.equal(refreshes, 3);

const lockPath = join(tmpdir(), `orbit-refresh-lock-test-${randomUUID()}.lock`);
const withRefreshLock = createFileLock({ lockPath, pollMs: 2, timeoutMs: 1_000 });
const lockEvents = [];
let releaseFirst;
const firstLock = withRefreshLock(async () => {
  lockEvents.push('first-start');
  await new Promise((resolve) => { releaseFirst = resolve; });
  lockEvents.push('first-end');
});
while (!releaseFirst) await new Promise((resolve) => setTimeout(resolve, 0));
const secondLock = withRefreshLock(async () => { lockEvents.push('second-start'); });
await new Promise((resolve) => setTimeout(resolve, 10));
assert.deepEqual(lockEvents, ['first-start']);
releaseFirst();
await Promise.all([firstLock, secondLock]);
assert.deepEqual(lockEvents, ['first-start', 'first-end', 'second-start']);

const staleLockPath = join(tmpdir(), `orbit-refresh-stale-test-${randomUUID()}.lock`);
await mkdir(staleLockPath);
await utimes(staleLockPath, new Date(0), new Date(0));
let staleRecovered = false;
await createFileLock({ lockPath: staleLockPath, staleMs: 1, timeoutMs: 100 })(async () => { staleRecovered = true; });
assert.equal(staleRecovered, true);

const blockedLockPath = join(tmpdir(), `orbit-refresh-timeout-test-${randomUUID()}.lock`);
await mkdir(blockedLockPath);
await assert.rejects(
  createFileLock({ lockPath: blockedLockPath, staleMs: 60_000, timeoutMs: 5, pollMs: 1 })(async () => {}),
  /Timed out waiting for the owner-session refresh lock/,
);
await rmdir(blockedLockPath);

const sharedLockPath = join(tmpdir(), `orbit-refresh-cache-test-${randomUUID()}.lock`);
const sharedRefreshLock = createFileLock({ lockPath: sharedLockPath, pollMs: 1, timeoutMs: 1_000 });
const rotatingSession = { publishable_key: 'publishable-shared', refresh_token: 'refresh-shared-0' };
const observedRefreshTokens = [];
let sharedRefreshes = 0;
const cacheOptions = {
  readSession: async () => ({ ...rotatingSession }),
  refreshSession: async (saved) => {
    observedRefreshTokens.push(saved.refresh_token);
    sharedRefreshes += 1;
    return { access_token: `shared-access-${sharedRefreshes}`, refresh_token: `refresh-shared-${sharedRefreshes}`, expires_in: 120 };
  },
  saveSession: async (_saved, token) => { rotatingSession.refresh_token = token; },
  withRefreshLock: sharedRefreshLock,
};
const cacheA = createCredentialCache(cacheOptions);
const cacheB = createCredentialCache(cacheOptions);
await Promise.all([cacheA(), cacheB()]);
assert.deepEqual(observedRefreshTokens, ['refresh-shared-0', 'refresh-shared-1']);
assert.equal(rotatingSession.refresh_token, 'refresh-shared-2');

console.log('orbit-credential-cache: passed');
