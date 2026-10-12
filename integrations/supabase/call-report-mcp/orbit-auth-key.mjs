export function parseStoredPublishableKey(secret) {
  if (typeof secret !== 'string' || secret.trim() === '') return null;
  try {
    const parsed = JSON.parse(secret.trim());
    return typeof parsed.publishable_key === 'string' && parsed.publishable_key.trim()
      ? parsed.publishable_key.trim()
      : null;
  } catch {
    return null;
  }
}

export function readStoredPublishableKey({ execFileSync, service, account }) {
  try {
    const secret = execFileSync(
      '/usr/bin/security',
      ['find-generic-password', '-s', service, '-a', account, '-w'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
    );
    return parseStoredPublishableKey(secret);
  } catch {
    return null;
  }
}

