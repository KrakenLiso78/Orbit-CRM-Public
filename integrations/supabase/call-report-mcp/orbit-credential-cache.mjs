/**
 * In-process renewable credential cache. Dependencies are injected so the
 * MCP bridge can keep Keychain and network concerns outside this unit.
 */
export function createCredentialCache({
  readSession,
  refreshSession,
  saveSession,
  withRefreshLock = async (operation) => operation(),
  now = () => Date.now(),
  safetyWindowMs = 60_000,
}) {
  let cached = null;
  let refreshPromise = null;

  return async function credentials() {
    const saved = await readSession();
    const currentTime = now();
    if (cached && cached.publishableKey === saved.publishable_key && cached.expiresAt > currentTime + safetyWindowMs) return cached;
    if (refreshPromise) return refreshPromise;

    refreshPromise = withRefreshLock(async () => {
      const currentSaved = await readSession();
      const refreshed = await refreshSession(currentSaved);
      if (typeof refreshed.access_token !== 'string') throw new Error('The refreshed owner session has no access token.');
      if (typeof refreshed.refresh_token === 'string') await saveSession(currentSaved, refreshed.refresh_token);
      cached = {
        accessToken: refreshed.access_token,
        publishableKey: currentSaved.publishable_key,
        expiresAt: now() + (Number.isFinite(refreshed.expires_in) ? refreshed.expires_in * 1000 : 3_000_000),
      };
      return cached;
    });
    try {
      return await refreshPromise;
    } finally {
      refreshPromise = null;
    }
  };
}
